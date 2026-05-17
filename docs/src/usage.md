# Usage

This page covers the moving pieces of the package — how to point it at a
different reference configuration, how to tweak CPP keys and namelists, how
to provide a pre-existing NEMO source tree, and how to launch under MPI.

## Where things live

```
NemoLibrary  →  one .dylib/.so handle + one run directory
NemoConfiguration  →  source path + build output dir + run dir + namelists
NemoNamelist  →  ordered (group, parameters) view of a Fortran namelist
```

The full workflow is always:

1. Get a NEMO source tree ([`download_nemo_source`](@ref) or your own clone).
2. Describe what to build ([`ORCA2_ICE_configuration`](@ref) or a hand-made
   [`NemoConfiguration`](@ref)).
3. Build the shared library ([`build_nemo_library`](@ref)).
4. Stage input data into the run directory (downloaders, or your own files).
5. Override namelist parameters ([`setup_run_directory`](@ref)).
6. Construct a [`NemoLibrary`](@ref) and drive it
   ([`initialize!`](@ref), [`step!`](@ref), [`finalize!`](@ref)).

Steps 1–4 are one-time setup; the per-session work is steps 5–6.

## Using a pre-existing NEMO source

If you already have a NEMO 4.2 checkout, point at it via the `NEMO_SOURCE`
environment variable and skip the clone:

```julia
ENV["NEMO_SOURCE"] = "/path/to/my/nemo-4.2"
source = download_nemo_source()         # returns ENV["NEMO_SOURCE"] without cloning
```

Or just pass the path directly to [`build_nemo_library`](@ref) — nothing
forces you to round-trip through `download_nemo_source`.

## Building a different reference configuration

[`ORCA2_ICE_configuration`](@ref) is a convenience helper. The general
pattern is to construct a [`NemoConfiguration`](@ref) directly:

```julia
configuration = NemoConfiguration(
    name             = "MY_GYRE",
    source           = source,
    output_directory = joinpath(homedir(), "nemo_gyre"),
    library_path     = joinpath(homedir(), "nemo_gyre", "libnemo.dylib"),
    run_directory    = joinpath(homedir(), "nemo_gyre", "run"),
    mpi              = false,
)
```

The build script currently hardcodes `ORCA2_ICE_PISCES` as the reference
configuration to copy from. To target a different REF\_CFG (`GYRE_PISCES`,
`AMM12`, `ORCA2_OFF_TRC`, …) you can either:

* invoke `lib/build_nemo_library.sh` directly and tweak the
  `reference_configuration` variable at the top, or
* point at an arbitrary existing config by setting `configuration_name` to a
  config that already exists in `cfgs/` — the script detects it and skips
  the `-r REF` copy step.

Smaller analytical configurations like `GYRE_PISCES` and `GYRE_BFM` do not
need [`download_orca2_ice_inputs`](@ref); the grid and forcing are
constructed analytically inside NEMO, so the run directory only needs the
namelists shipped in the REF\_CFG's `EXPREF/`.

## Tweaking CPP keys

The build script removes `key_top` (biogeochemistry) and `key_xios` (the
XML I/O server) before compiling, and adds `key_mpi_off` when MPI is
disabled. If you need different CPP keys, edit the small Python block in
`lib/build_nemo_library.sh` that adjusts `cpp_<configuration>.fcm` — keys
removed there will not be defined at compile time.

Common knobs:

| Key | Effect when defined |
|---|---|
| `key_qco` | Quasi-Eulerian vertical coordinate (default in ORCA2). Selects `stp_MLF` in `stpmlf` instead of `stp` in `step`. |
| `key_si3` | SI3 sea ice. |
| `key_top` | Top-tracer module (PISCES requires this). |
| `key_xios` | Use XIOS for I/O (requires the XIOS library on disk). |
| `key_mpi_off` | Compile without MPI. |
| `key_agrif` | AGRIF nesting. Not yet supported by the wrapper. |

## Overriding namelist parameters

[`setup_run_directory`](@ref) takes a `Dict{Tuple, Any}` keyed by
`(filename, group, parameter)`. The namelist file is read into a
[`NemoNamelist`](@ref), the parameter is updated, and the file is written
back. Group and parameter names use `Symbol`s; filenames are strings.

```julia
setup_run_directory(configuration; overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend)  => 100,
    ("namelist_cfg", :namrun, :nn_stock)  => 999999,
    ("namelist_cfg", :namdom, :rn_Dt)     => 1800.0,
    ("namelist_ice_cfg", :nampar, :ln_icediachk) => true,
))
```

To read or write namelists outside the configuration workflow, use
[`read_namelist`](@ref) and [`write_namelist`](@ref) directly. Namelists
round-trip through `Int`, `Float64`, `Bool`, `String`, and `Vector` values
(Fortran `d`-exponents in floats are recognized).

## Running with MPI

Build with `mpi = true` and `--mpi` passed to the script (the
[`build_nemo_library`](@ref) wrapper handles this if you set
`configuration.mpi = true` and pass the flag through). The build script
expects `mpifort` (or `mpif90`) on `PATH` and uses its directory as
`MPI_HOME`.

On the Julia side, install `MPI` and `MPIPreferences` in your project and
configure MPI.jl to use the same MPI runtime the library is linked
against:

```julia
using MPIPreferences
MPIPreferences.use_system_binary(library_names = ["libmpi"],
                                  extra_paths   = ["/path/to/mpi/lib"])
```

Then a minimal MPI script looks like:

```julia
using MPI
using NEMO

MPI.Init()
library = NemoLibrary(library_path, run_directory;
                     verbose = false,
                     mpi_communicator = Int32(MPI.COMM_WORLD.val))
initialize!(library)
for _ in 1:N; step!(library); end
MPI.Barrier(MPI.COMM_WORLD)
finalize!(library)        # also runs NEMO's mppstop, which calls MPI_Finalize
MPI.Finalize()             # no-op if NEMO already finalized MPI
```

Launch with `mpiexec -n <ranks> julia --project ...`. NEMO does its own
domain decomposition based on `jpni`/`jpnj` in `namelist_cfg` (or the
number of ranks if those are zero).

The wrapper currently passes `mpi_communicator` to NEMO but NEMO uses
`MPI_COMM_WORLD` internally; passing a subset communicator from Julia
requires patching `lib_mpp.F90` to honour an external communicator and is
not yet supported. For v0.1, MPI mode means "all of `MPI_COMM_WORLD` runs
NEMO".

## Error handling

Every fatal Fortran `STOP` from NEMO (bad namelist, missing input file,
blown CFL, MPI abort, …) is intercepted by the C error handler in
`lib/nemo_error_handler.c` and re-thrown as a [`NemoError`](@ref). The
Julia process keeps running, the error message is preserved, and the
shared library can be unloaded and reloaded in the same session.

Some failure modes inside NEMO take signal paths the wrapper does not yet
intercept (raw `SEGV` from a downstream access after a soft failure, for
instance). Those still crash the Julia process. Setting `verbose = true`
on the [`NemoLibrary`](@ref) lets NEMO write to the REPL directly so you
can see what it was doing; setting `verbose = false` captures the same
output to `<run_directory>/nemo_stdout.log`.
