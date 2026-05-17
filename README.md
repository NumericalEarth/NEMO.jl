# NEMO.jl

[![Docs (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://simone-silvestri.github.io/NEMO.jl/stable)
[![Docs (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://simone-silvestri.github.io/NEMO.jl/dev)
[![CI](https://github.com/simone-silvestri/NEMO.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/simone-silvestri/NEMO.jl/actions/workflows/ci.yml)
[![Documentation](https://github.com/simone-silvestri/NEMO.jl/actions/workflows/docs.yml/badge.svg)](https://github.com/simone-silvestri/NEMO.jl/actions/workflows/docs.yml)

Julia interface to the [NEMO](https://www.nemo-ocean.eu) ocean model. Build NEMO
as a shared library, drive it from Julia with `initialize!` / `step!` /
`finalize!`, and read or write prognostic state and surface forcing at every
step.

One `NemoLibrary` struct owns one shared-library handle and one run directory,
and every operation hangs off it.

* Target NEMO version: **4.2.x**
* First reference configuration: **ORCA2_ICE** (global 2° ORCA grid + SI3 sea
  ice, no biogeochemistry)
* MPI is supported via [`MPI.jl`](https://github.com/JuliaParallel/MPI.jl)

## Quickstart

```julia
using NEMO

source           = download_nemo_source()
configuration    = ORCA2_ICE_configuration(source = source,
                                           output_directory = "/scratch/nemo_orca2_ice",
                                           mpi = false)
library_path     = build_nemo_library(configuration.source,
                                      configuration.output_directory,
                                      configuration.name)

download_orca2_ice_inputs(configuration.run_directory)

setup_run_directory(configuration; overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend) => 10,
    ("namelist_cfg", :namrun, :nn_stock) => 999999,
))

library = NemoLibrary(configuration.library_path,
                      configuration.run_directory; verbose = false)

initialize!(library)
@info "Grid" library.dimensions
@info "Working precision (bytes)" get_working_precision(library)

temperature = zeros(Float64, library.dimensions.Nie0 - library.dimensions.Nis0 + 1,
                             library.dimensions.Nje0 - library.dimensions.Njs0 + 1,
                             library.dimensions.jpk)

for _ in 1:10
    step!(library)
    get_temperature!(library, temperature)
    @info "step" iteration=get_iteration_count(library) mean_T=sum(temperature) / length(temperature)
end

finalize!(library)
```

## Package layout

```
src/
  NEMO.jl              module entry, includes + exports
  Types.jl             NemoLibrary, NemoConfiguration, NemoError, NemoNamelist
  Source.jl            shallow-clone NEMO 4.2 from forge.nemo-ocean.eu
  Build.jl             Julia wrapper around lib/build_nemo_library.sh
  Library.jl           dlopen + initialize! / step! / finalize!
  Fields.jl            3D and 2D state get!/set!, grid getters
  Forcing.jl           surface-forcing get!/set!
  Namelists.jl         Fortran namelist read / write
  Configurations.jl    ORCA2_ICE configuration helpers
  RunDirectory.jl      assemble run directory + apply namelist overrides
lib/
  nemo_wrapper.F90     bind(C) module exposing NEMO state to Julia
  nemo_error_handler.c intercepts Fortran STOP, longjmps back to Julia
  build_nemo_library.sh  makenemo + link into libnemo.{dylib,so}
```

## Requirements

* Julia 1.10+
* `gfortran`, `cc`, `make`, `git`
* `netcdf-c` and `netcdf-fortran` (with `nc-config` and `nf-config` on `PATH`)
* For MPI builds: `mpifort` on `PATH` (or set `MPI_HOME`)

## Roadmap

| Version | Scope |
|---|---|
| v0.1.0 | ORCA2_ICE single-rank, full state / forcing get-set, namelist I/O, build pipeline |
| v0.2.0 | MPI multi-rank via `MPI.jl`, decomposed accessors |
| v0.3.0 | Output reading (`NCDatasets` ext), run-directory scanning |
| v0.4.0 | Additional REF_CFGs (GYRE, AMM12) |
| v0.5.0+ | AGRIF nesting, SI3 sea-ice exposure, `ClimateModels.jl` integration |

See [`docs/plans/2026-05-16-nemo-jl-design.md`](docs/plans/2026-05-16-nemo-jl-design.md) for the full design.
