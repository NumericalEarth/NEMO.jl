# # [Driving ORCA2_ICE from Julia](@id orca2-ice-example)
#
# This example walks through a full in-process NEMO simulation driven from
# Julia: clone the NEMO 4.2 source, build it as a shared library, fetch the
# standard ORCA2_ICE forcing archive, initialize the model, integrate a few
# time steps while reading and modifying the prognostic state, and shut
# everything down cleanly.
#
# ORCA2_ICE is NEMO's reference global 2° ocean configuration with SI3 sea
# ice. We deliberately compile it without biogeochemistry (`key_top`) and
# without XIOS (`key_xios`) so the build is self-contained — Julia reads
# the model state directly via [`get_temperature!`](@ref) and friends, so
# we don't need an XML I/O server.

using NEMO

# We keep everything under one scratch directory so the build, run directory,
# and intermediate outputs sit side-by-side.

const SCRATCH_OUTPUT  = get(ENV, "NEMO_OUTPUT", joinpath(homedir(), "nemo_orca2_ice"))
const FINAL_ITERATION = 10

# ### Source, build, and forcing data
#
# [`download_nemo_source`](@ref) shallow-clones NEMO 4.2.x from
# `forge.nemo-ocean.eu` into a `Scratch.jl`-backed cache. Re-running on a
# subsequent session returns the cached path with no network traffic.

source = download_nemo_source()

# [`ORCA2_ICE_configuration`](@ref) describes the build: where the source
# tree lives, where to put the shared library and run directory, and whether
# MPI is enabled. It does **not** trigger the build — it just bundles
# arguments for the next call.

configuration = ORCA2_ICE_configuration(source           = source,
                                        output_directory = SCRATCH_OUTPUT,
                                        mpi              = false)

# [`build_nemo_library`](@ref) invokes the shell pipeline in
# `lib/build_nemo_library.sh`: it generates a `julia-<platform>.fcm` arch
# file, copies our Fortran wrapper into `MY_SRC/`, runs `makenemo`, and
# re-links the resulting `.o` files (everything except `nemo.o`'s
# `PROGRAM nemo_gcm`) into `libnemo.{dylib,so}`. The first build takes a
# few minutes; subsequent builds reuse the cached objects and only relink.

build_nemo_library(configuration.source,
                   configuration.output_directory,
                   configuration.name)

# [`download_orca2_ice_inputs`](@ref) fetches the standard NEMO SETTE input
# archive (`ORCA2_ICE_v4.2.0.tar.gz`, ~700 MB) and extracts the
# bathymetry, mesh, climatologies, and CORE-IA atmospheric forcing into the
# run directory. The tarball is cached, so re-extracting is fast.

download_orca2_ice_inputs(configuration.run_directory)

# We override two namelist parameters for the example: `nn_itend` controls
# how many time steps to integrate, and `nn_stock` (frequency of restart
# writes) is pushed past the end so the example doesn't write a restart.

setup_run_directory(configuration; overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend) => FINAL_ITERATION,
    ("namelist_cfg", :namrun, :nn_stock) => 999999,
))

# ### Loading the library
#
# A [`NemoLibrary`](@ref) ties one shared-library handle to one run
# directory. Setting `verbose = false` captures NEMO's Fortran stdout into
# `<run_dir>/nemo_stdout.log` instead of cluttering the REPL.

library = NemoLibrary(configuration.library_path,
                      configuration.run_directory; verbose = false)

# [`initialize!`](@ref) `dlopen`s the library, runs NEMO's `nemo_init`
# (which reads namelists and the domain configuration), then populates
# `library.dimensions` and `library.working_precision`.
#
# If NEMO hits a fatal `STOP` — bad namelist, missing input file, blown
# CFL — the C error handler intercepts it and re-throws as a Julia
# [`NemoError`](@ref); the Julia process keeps running.

initialize!(library)

@info "Grid"              library.dimensions
@info "Working precision" get_working_precision(library)
@info "Initial timestep"  get_timestep(library)

# ### Reading state at every step
#
# All getters return per-rank interior arrays of shape
# `(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1[, jpk])`. We pre-allocate once and
# reuse the buffers across time steps to avoid GC churn.

zonal_size      = library.dimensions.Nie0 - library.dimensions.Nis0 + 1
meridional_size = library.dimensions.Nje0 - library.dimensions.Njs0 + 1
vertical_size   = library.dimensions.jpk

temperature   = zeros(Float64, zonal_size, meridional_size, vertical_size)
sea_surface_η = zeros(Float64, zonal_size, meridional_size)

# [`step!`](@ref) advances NEMO by one time step (`stp_MLF` under
# `key_qco`). After each step we copy the active temperature tracer and the
# free-surface anomaly out of NEMO's memory.

for iteration in 1:FINAL_ITERATION
    step!(library)
    get_temperature!(library, temperature)
    get_sea_surface_height!(library, sea_surface_η)
    @info("step",
          iteration = get_iteration_count(library),
          time      = get_simulation_time(library),
          mean_T    = sum(temperature)   / length(temperature),
          mean_η    = sum(sea_surface_η) / length(sea_surface_η))
end

# ### Shutdown
#
# [`finalize!`](@ref) closes NEMO's open NetCDF files, calls `mppstop` so
# MPI (when present) is shut down from NEMO's side first, then `dlclose`s
# the library and cleans up the temporary copy.

finalize!(library)
