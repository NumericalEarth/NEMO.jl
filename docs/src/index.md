# NEMO.jl

🌊 Drive the [NEMO](https://www.nemo-ocean.eu) ocean model from Julia. NEMO is
built once as a shared library, loaded into Julia with `dlopen`, and stepped
with `initialize!` / `step!` / `finalize!`. Prognostic state and surface
forcing are read and written in-process.

One [`NemoLibrary`](@ref) struct owns one shared-library handle and one run
directory, and every operation hangs off it.

* Target NEMO version: **4.2.x**
* First reference configuration: **ORCA2_ICE** (global 2° ORCA grid + SI3 sea
  ice, no biogeochemistry)
* MPI is supported via [`MPI.jl`](https://github.com/JuliaParallel/MPI.jl)

## Installation

NEMO.jl is not yet registered. Install from the GitHub source:

```julia
julia> using Pkg

julia> Pkg.add(url = "https://github.com/NumericalEarth/NEMO.jl")
```

Building the shared library requires:

* `gfortran`, `cc`, `make`, `git`
* `netcdf-c` and `netcdf-fortran` (with `nc-config` and `nf-config` on `PATH`)
* For MPI builds: `mpifort` on `PATH` (or `MPI_HOME` exported)

On macOS this is satisfied by `brew install gcc git` plus a conda environment
with `netcdf-fortran` (and `mpich` for MPI). On Linux, `apt-get install
gfortran libnetcdf-dev libnetcdff-dev` is usually enough.

## Quick start

The full ORCA2_ICE walkthrough lives in
[ORCA2_ICE smoke test](@ref orca2-ice-example); here is the compressed form.

```julia
using NEMO

source        = download_nemo_source()
configuration = ORCA2_ICE_configuration(source           = source,
                                        output_directory = joinpath(homedir(), "nemo_orca2"),
                                        mpi              = false)

build_nemo_library(configuration.source,
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
for _ in 1:10
    step!(library)
end
finalize!(library)
```

## Next steps

* The [Usage](usage.md) page explains how to point the package at a different
  reference configuration (`GYRE_BFM`, `AMM12`, custom CPP keys, MPI launches).
* The [Architecture](architecture.md) page describes the Fortran wrapper, the
  build pipeline, and the error-handling design.
* The literated [ORCA2_ICE smoke test](literated/ORCA2_ICE_step.md) is the
  full walkthrough.
* The [Library](library/outline.md) section is the API reference.
