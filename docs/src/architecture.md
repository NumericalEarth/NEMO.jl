# Architecture

NEMO is a Fortran 90 ocean model with a `PROGRAM nemo_gcm` entry point and
hundreds of internal modules. NEMO.jl never runs that program. Instead it
compiles every NEMO object file except `nemo.o` into a shared library,
loads the library into Julia with `dlopen`, and calls a small set of
`bind(C)` entry points that expose `nemo_init`, `stp`/`stp_MLF`, and the
prognostic state.

## The four layers

```
            ┌─────────────────────────────────────────────────┐
   Julia    │  NemoLibrary, initialize!, step!, finalize!,    │   src/Library.jl
   facing   │  get_temperature!, set_temperature!, …          │   src/Fields.jl
            └────────────────────────┬────────────────────────┘
                                     │ ccall
            ┌────────────────────────┴────────────────────────┐
   C        │  setjmp/longjmp around init/step/finalize;      │   lib/nemo_error_handler.c
   safety   │  override _gfortran_stop_string / exit / abort  │
            └────────────────────────┬────────────────────────┘
                                     │ bind(C) symbol
            ┌────────────────────────┴────────────────────────┐
   Fortran  │  nemo_internal_init / _step / _finalize         │   lib/nemo_wrapper.F90
   wrapper  │  nemo_get_* / nemo_set_* / nemo_get_grid_size   │
            └────────────────────────┬────────────────────────┘
                                     │ USE
            ┌────────────────────────┴────────────────────────┐
   NEMO     │  nemo_init, stp / stp_MLF, oce::ts/uu/vv/ww/ssh │   src/OCE/ …
            └─────────────────────────────────────────────────┘
```

## Fortran wrapper (`lib/nemo_wrapper.F90`)

A single Fortran 90 module that `USE`s NEMO's public modules
(`par_oce`, `dom_oce`, `oce`, `sbc_oce`, `nemogcm`, `step` / `stpmlf`,
`in_out_manager`, `iom`, `lib_mpp`) and exposes C-callable subroutines via
`iso_c_binding`'s `bind(C, name='…')`. Using explicit C names removes
compiler-dependent Fortran name mangling.

The wrapper does three things:

1. **Lifecycle.** `nemo_internal_init(mpi_communicator)` calls `nemo_init`
   and seeds `current_step` from `nit000 - 1`. `nemo_internal_step()`
   increments `current_step` and dispatches to `stp_MLF(current_step)`
   under `key_qco` (else `stp(current_step)`).
   `nemo_internal_finalize()` calls `iom_close` then `mppstop` (which
   shuts down MPI when MPI is active).

2. **Introspection.** `nemo_get_grid_size`, `nemo_get_iteration_count`,
   `nemo_get_simulation_time`, `nemo_get_timestep`, `nemo_get_working_precision`,
   `nemo_set_timestep`.

3. **State get/set.** Per-rank copies of the interior region
   (`Nis0:Nie0, Njs0:Nje0[, jpk]`) for the active temperature and
   salinity tracers, the three velocity components, the free-surface
   anomaly, and the surface forcing fields (wind stress, solar/non-solar
   heat flux, freshwater flux, salt flux). Grid getters return cell
   longitude/latitude/depth/horizontal sizes and the bottom-level index.

The wrapper hides one structural quirk of NEMO 4.2: when `key_qco` is
defined the time step is in module `stpmlf` (routine `stp_MLF`), but when
neither `key_qco` nor `key_linssh` is defined the time step is in module
`step` (routine `stp`). The wrapper dispatches between them with a CPP
guard so the same Julia API works either way.

## C error handler (`lib/nemo_error_handler.c`)

NEMO terminates fatally via `ctl_stop` → `mppstop` → `STOP <code>`, which
translates to `_gfortran_stop_numeric`, `_gfortran_stop_string`, or
`_gfortran_error_stop_string` depending on the Fortran flavour. The
handler:

1. Defines its own versions of those symbols (plus `_gfortran_exit_i4`,
   `_gfortran_exit_i8`, `_gfortran_abort`). When the wrapper is linked,
   these override libgfortran's at link time.
2. Each override captures the message into a static buffer and, if a
   safe wrapper is currently armed, `siglongjmp`s back to the safe-wrapper
   entry. If no wrapper is armed (e.g., a `STOP` during library load), it
   prints the message and `_exit`s.
3. Exposes `nemo_initialize`, `nemo_step`, `nemo_finalize` as C
   wrappers that `sigsetjmp` before calling the Fortran routines and
   return a non-zero status on `longjmp`. Julia checks the status and
   throws [`NemoError`](@ref) with the captured message.

This is exactly the trick that makes `dlopen` + Fortran usable from a
long-running Julia process: without it, the first `STOP` in NEMO kills
the REPL.

## Build script (`lib/build_nemo_library.sh`)

The script is bash; it:

1. Generates an `arch/arch-julia-<platform>.fcm` file with
   `gfortran`, `-fPIC` everywhere, `-fallow-argument-mismatch` (NEMO's
   MPI dummy-arg patterns trip modern gfortran), and `netcdf-c` /
   `netcdf-fortran` flags resolved from `nc-config` / `nf-config`.
2. Creates a new configuration in `cfgs/<name>` by copying
   `ORCA2_ICE_PISCES` via `makenemo -r ORCA2_ICE_PISCES -n <name>`.
3. Edits the new `cpp_<name>.fcm` directly with a Python one-liner —
   makenemo's own `del_key` uses GNU-sed `\b` patterns that fail
   silently on macOS BSD sed.
4. Drops `nemo_wrapper.F90` into `MY_SRC/`.
5. Compiles via `makenemo -m julia-<platform> -j N`.
6. Re-links every `.o` (except `nemo.o`, which contains
   `PROGRAM nemo_gcm`) into `libnemo.{dylib,so}`, adding the compiled
   error handler.
7. Copies the configuration's `EXP00` (or `EXPREF`) into the run
   directory and symlinks the shared library next to the namelists.

The script is idempotent: rerunning against the same configuration
reuses cached objects and only relinks.

## Julia side (`src/Library.jl`)

`load!` copies the `.dylib` to `tempname() * ".dylib"` before `dlopen`. On
macOS, dyld caches handles per path — without the temp-copy, reloading the
same `.dylib` in one Julia session silently returns the stale image.

`in_run_directory` `cd`s into the run directory before each NEMO call
because Fortran reads/writes a lot relative to CWD. Paths are
`abspath`'d at [`NemoLibrary`](@ref) construction so the `cd` doesn't
strand subsequent operations.

`with_output_control` redirects fd 1 and 2 to
`<run_directory>/nemo_stdout.log` when `verbose = false`. The earlier
implementation pointed them at `/dev/null`, which broke NEMO's own
`OPEN(UNIT=24, FILE='/dev/null', …)` for its `numnul` unit.

## MPI design

When the library is built with `--mpi`, NEMO links against the same MPI
runtime its build script found via `mpifort` on `PATH`. From Julia:

* Install `MPI` and `MPIPreferences`; set `MPIPreferences.use_system_binary`
  pointed at the same MPI library directory.
* `MPI.Init()` *before* constructing the [`NemoLibrary`](@ref). NEMO's
  `mpp_start` checks `MPI_INITIALIZED` and skips its own `MPI_Init` when
  Julia has already initialized MPI.
* On shutdown, [`finalize!`](@ref) calls `mppstop`, which (when MPI is
  active) calls `MPI_Finalize` from NEMO's side. A subsequent
  `MPI.Finalize()` from Julia is a no-op.

`mpi_communicator` on the Julia side currently flows through to the
wrapper as a `c_int` but NEMO ignores it; subset communicators require a
small patch to `lib_mpp.F90` that the package will add in v0.2.

## Future-proofing

Three pieces are version-coupled to NEMO 4.2:

| Piece | Coupling |
|---|---|
| Fortran wrapper imports | NEMO 4.2 module/variable names (`step`, `stpmlf`, `ts`, `uu`, `vv`, `ww`, `ssh`, `Nbb/Nnn/Naa`, `Nis0`/`Nie0`/…) |
| Build script | `makenemo` interface, `cfgs/` layout, FCM arch format |
| Error handler | gfortran ABI for `_gfortran_*` runtime functions |

When NEMO 5.0 ships, only the Fortran wrapper file needs a new variant
(`lib/nemo_wrapper_v50.F90`) selected at build time. The Julia API,
the C handler, and the build pipeline stay the same.
