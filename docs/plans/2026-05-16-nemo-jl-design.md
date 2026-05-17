# NEMO.jl — Design Document

**Date:** 2026-05-16
**Status:** Validated, ready for v0.1.0 implementation

## Purpose

NEMO.jl is a Julia interface to the NEMO ocean model. The primary use case is the **in-process library path**: NEMO is built as a shared library (`libnemo.so` / `libnemo.dylib`), loaded into Julia via `dlopen`, and driven through `initialize!` / `step!` / `finalize!` calls.

The package targets **NEMO 4.2.x** as its first supported version family and **ORCA2_ICE** (global 2° ORCA grid with SI3 sea ice, no PISCES biogeochemistry) as the first reference configuration. **MPI is supported from v0.1** via `MPI.jl`.

## Design philosophy

- One struct, `NemoLibrary`, owns one shared-library handle and one run directory. No global state beyond `dlopen`.
- Versioning is explicit: the Fortran wrapper is pinned to NEMO 4.2.x. NEMO 5.0 will get its own wrapper file selected at build time, not at Julia load time.
- The C-callable surface (the wrapper's `bind(C)` exports) is the ABI boundary. Adding exports is additive and non-breaking; removing or renaming requires a major bump.
- Weak dependencies for optional capabilities (NetCDF output reading, MeshArrays-style grids). Users doing online coupling don't pay for them.

## Package layout

```
NEMO.jl/
├── Project.toml
├── src/
│   ├── NEMO.jl              module entry, includes + exports
│   ├── Types.jl             NemoLibrary, NemoConfiguration, NemoError, NemoNamelist
│   ├── Source.jl            download / clone NEMO 4.2 source
│   ├── Build.jl             call build_nemo_library.sh, manage arch files
│   ├── Library.jl           dlopen/dlclose, ccall wrappers, initialize! / step! / finalize!
│   ├── Fields.jl            3D and 2D field get!/set! accessors
│   ├── Forcing.jl           surface forcing get!/set! accessors
│   ├── Namelists.jl         read / write NEMO Fortran namelists
│   ├── Configurations.jl    ORCA2_ICE setup helpers, REF_CFG discovery
│   ├── RunDirectory.jl      assemble run directory from REF_CFG + user inputs
│   └── Output.jl            NCDatasets-backed readers (weak-dep extension)
├── lib/
│   ├── nemo_wrapper.F90     bind(C) module exposing NEMO state to Julia
│   ├── nemo_error_handler.c intercepts Fortran STOP; longjmp back to Julia
│   └── build_nemo_library.sh  shell builder: clone arch, makenemo, link shared library
├── test/
├── examples/
└── docs/
```

## Fortran wrapper

`lib/nemo_wrapper.F90` is a Fortran 90 module using `iso_c_binding` and `bind(C)` to expose C-callable symbols with explicit names (no compiler-dependent mangling). It `use`s NEMO modules directly: `nemogcm`, `step`, `oce`, `dom_oce`, `sbc_oce`, `lib_mpp`.

### C exports (v0.1)

**Lifecycle**
```
nemo_initialize(mpi_communicator, ierr)
nemo_step(ierr)
nemo_finalize()
```

**Introspection**
```
nemo_get_grid_size(jpi, jpj, jpk, Nis0, Nie0, Njs0, Nje0)
nemo_get_iteration_count(nit)
nemo_get_simulation_time(time)
nemo_get_timestep(dt)
nemo_set_timestep(dt)
nemo_get_working_precision(wp_bytes)
```

**3D state get / set**
```
nemo_get_potential_temperature(array_3d)   nemo_set_potential_temperature(array_3d)
nemo_get_salinity(array_3d)                nemo_set_salinity(array_3d)
nemo_get_zonal_velocity(array_3d)          nemo_set_zonal_velocity(array_3d)
nemo_get_meridional_velocity(array_3d)     nemo_set_meridional_velocity(array_3d)
nemo_get_vertical_velocity(array_3d)
```

**2D state get / set**
```
nemo_get_sea_surface_height(array_2d)      nemo_set_sea_surface_height(array_2d)
```

**Surface forcing get / set**
```
nemo_get_zonal_wind_stress       nemo_set_zonal_wind_stress
nemo_get_meridional_wind_stress  nemo_set_meridional_wind_stress
nemo_get_nonsolar_heat_flux      nemo_set_nonsolar_heat_flux
nemo_get_solar_radiation         nemo_set_solar_radiation
nemo_get_freshwater_flux         nemo_set_freshwater_flux
nemo_get_salt_flux               nemo_set_salt_flux
```

**Grid (get-only)**
```
nemo_get_cell_longitude(array_2d)
nemo_get_cell_latitude(array_2d)
nemo_get_cell_depth(array_1d)
nemo_get_cell_zonal_size(array_2d)
nemo_get_cell_meridional_size(array_2d)
nemo_get_bottom_level_index(array_2d)
```

Each `nemo_get_*` / `nemo_set_*` copies interior-domain data between NEMO's tiled arrays and a flat per-rank array of size `(Nie0-Nis0+1, Nje0-Njs0+1[, jpk])`.

### Error handling

`lib/nemo_error_handler.c` overrides `_gfortran_stop_string` and `_gfortran_error_stop_string` at link time. When NEMO calls `ctl_stop` (or any internal `STOP`), the handler captures the message into a static buffer and `longjmp`s back into the most recent safe-wrapper entry point. The safe wrapper returns a non-zero `ierr`; Julia reads the message via `nemo_get_error_message` and throws `NemoError`.

### MPI

`lib_mpp.F90` is patched (the patched copy lives in `lib/MY_SRC_patches/`) to accept an external MPI communicator passed through `nemo_initialize`. When `mpi_communicator == MPI_COMM_NULL`, the build runs without MPI; when a real communicator is passed (from `MPI.jl`), NEMO skips its own `MPI_Init` and uses the provided one.

## Julia API

```julia
mutable struct NemoLibrary
    handle           :: Ptr{Nothing}
    library_path     :: String
    run_directory    :: String
    temporary_path   :: String
    dimensions       :: @NamedTuple{jpi::Int, jpj::Int, jpk::Int,
                                    Nis0::Int, Nie0::Int,
                                    Njs0::Int, Nje0::Int}
    initialized      :: Bool
    verbose          :: Bool
    mpi_communicator :: Int32
end

initialize!(lib::NemoLibrary)
step!(lib::NemoLibrary)
finalize!(lib::NemoLibrary)

get_iteration_count(lib)   ::Int
get_simulation_time(lib)   ::Float64
get_timestep(lib)          ::Float64
set_timestep!(lib, dt)

get_potential_temperature!(lib, array_3d)
set_potential_temperature!(lib, array_3d)
# ... and so on for all field accessors
```

The temp-copy `dlopen` trick (copy library to `tempname()` before `dlopen`) is essential on macOS, where dyld caches handles per path. Reloading the same path silently returns the stale image.

## Build pipeline

`lib/build_nemo_library.sh` accepts:

```
build_nemo_library.sh NEMO_SOURCE OUTPUT_DIR CONFIG_NAME [--mpi]
```

Flow:
1. Shallow-clone NEMO 4.2.x from `forge.nemo-ocean.eu` if `NEMO_SOURCE` is empty.
2. Stage `ORCA2_ICE_PISCES` REF_CFG, then strip `key_top` and `key_pisces` from `cpp_*.fcm` to drop biogeochemistry.
3. Drop `nemo_wrapper.F90` and the patched `lib_mpp.F90` into `MY_SRC/`.
4. Generate `arch-julia-{darwin,linux}.fcm` with `-fPIC` everywhere. When `--mpi` is set, resolve `MPI_HOME` from `mpifort` on `PATH` (so `MPI_jll`'s `mpifort` works transparently).
5. Run `makenemo -m julia -r ORCA2_ICE -n MY_CFG`.
6. Re-link `.o` files (excluding `nemo.f90`'s `PROGRAM nemo_gcm` object) into `libnemo.{dylib,so}`.
7. Set up `OUTPUT_DIR/run/` with `namelist_cfg`, `namelist_ice_cfg`, and symlinks to bathymetry / forcing data.

## Future-proofing

| Concern | Strategy |
|---|---|
| NEMO version upgrades (5.0+) | New `nemo_wrapper_v50.F90`, selected at build time. Julia API unchanged. |
| Adding fields | Additive ccall; no breaking change. |
| Precision (single vs double) | Query `nemo_get_working_precision` at init; wrapper coerces to `c_double` so Julia sees uniform `Float64`. |
| Output reading | Weak-dep `NCDatasets` extension — users who only do online coupling don't pull it. |
| Grid representations | Weak-dep `MeshArrays` extension. |
| AGRIF nesting | Deferred to v0.5. Wrapper architecture is compatible (one wrapper per nest level). |
| `ClimateModels.jl` orchestration | Deferred to v0.5. Optional; library users don't need it. |

## Roadmap

| Version | Scope |
|---|---|
| v0.1.0 | ORCA2_ICE single-rank. Full lifecycle, state get / set, forcing get / set, namelist I/O, build pipeline for darwin + linux. |
| v0.2.0 | MPI multi-rank via `MPI.jl`. Decomposed field accessors. |
| v0.3.0 | Output reading (`NCDatasets` ext), run-directory scanning, verification helpers. |
| v0.4.0 | Additional REF_CFGs (GYRE, AMM12). Namelist diff / merge tooling. |
| v0.5.0+ | AGRIF nesting hooks. SI3 sea-ice field exposure. Optional `ClimateModels.jl` integration. |
