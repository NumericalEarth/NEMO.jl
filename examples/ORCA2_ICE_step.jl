# # [Driving ORCA2_ICE from Julia](@id orca2-ice-example)
#
# This example walks through a full in-process NEMO simulation driven from Julia: clone the NEMO 4.2 source,
# build it as a shared library, fetch the standard ORCA2_ICE forcing archive, initialize the model, integrate
# a few time steps while reading the prognostic state, and shut everything down cleanly. Along the way we
# visualize the initial surface temperature and animate the evolution of the sea-surface height.
#
# ORCA2_ICE is NEMO's reference global 2° ocean configuration with SI3 sea ice. We deliberately compile it
# without biogeochemistry (`key_top`) and without XIOS (`key_xios`) so the build is self-contained — Julia
# reads the model state directly via [`get_temperature!`](@ref) and friends, so we don't need an XML I/O
# server.

using NEMO
using CairoMakie

# We keep everything under one scratch directory so the build, run directory, and intermediate outputs sit
# side-by-side.

const SCRATCH_OUTPUT  = get(ENV, "NEMO_OUTPUT", joinpath(homedir(), "nemo_orca2_ice"))
const FINAL_ITERATION = 1500

# ### Source, build, and forcing data
#
# [`download_nemo_source`](@ref) shallow-clones NEMO 4.2.x from `forge.nemo-ocean.eu` into a
# `Scratch.jl`-backed cache. Re-running on a subsequent session returns the cached path without network
# traffic.

source = download_nemo_source()

# [`ORCA2_ICE_configuration`](@ref) describes the build: where the source tree lives, where to put the shared
# library and run directory, and whether MPI is enabled. It does **not** trigger the build — it just bundles
# arguments for the next call.

configuration = ORCA2_ICE_configuration(source = source, output_directory = SCRATCH_OUTPUT, mpi = false)

# [`build_nemo_library`](@ref) invokes the shell pipeline in `lib/build_nemo_library.sh`: it generates a
# `julia-<platform>.fcm` arch file, copies our Fortran wrapper into `MY_SRC/`, runs `makenemo`, and re-links
# the resulting `.o` files (everything except `nemo.o`'s `PROGRAM nemo_gcm`) into `libnemo.{dylib,so}`. The
# first build takes a few minutes; subsequent builds reuse the cached objects and only relink.

build_nemo_library(configuration.source, configuration.output_directory, configuration.name)

# [`download_orca2_ice_inputs`](@ref) fetches the standard NEMO SETTE input archive
# (`ORCA2_ICE_v4.2.0.tar.gz`, ~700 MB) and extracts the bathymetry, mesh, climatologies, and CORE-IA
# atmospheric forcing into the run directory. The tarball is cached, so re-extracting is fast.

download_orca2_ice_inputs(configuration.run_directory)

# We override two namelist parameters for the example: `nn_itend` controls how many time steps to integrate,
# and `nn_stock` (frequency of restart writes) is pushed past the end so the example doesn't write a restart.

setup_run_directory(configuration; overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend) => FINAL_ITERATION,
    ("namelist_cfg", :namrun, :nn_stock) => 999999,
))

# ### Loading the library
#
# A [`NemoLibrary`](@ref) ties one shared-library handle to one run directory. Setting `verbose = false`
# captures NEMO's Fortran stdout into `<run_dir>/nemo_stdout.log` instead of cluttering the REPL.

library = NemoLibrary(configuration.library_path, configuration.run_directory; verbose = false)

# [`initialize!`](@ref) `dlopen`s the library, runs NEMO's `nemo_init` (which reads namelists and the domain
# configuration), then populates `library.dimensions` and `library.working_precision`.
#
# If NEMO hits a fatal `STOP` — bad namelist, missing input file, blown CFL — the C error handler
# intercepts it and re-throws as a Julia [`NemoError`](@ref); the Julia process keeps running.

initialize!(library)

@info "Grid"              library.dimensions
@info "Working precision" get_working_precision(library)
@info "Initial timestep"  get_timestep(library)

# ### Reading state at every step
#
# All getters return per-rank interior arrays of shape `(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1[, jpk])`. We
# pre-allocate once and reuse the buffers across time steps to avoid GC churn.

zonal_size      = library.dimensions.Nie0 - library.dimensions.Nis0 + 1
meridional_size = library.dimensions.Nje0 - library.dimensions.Njs0 + 1
vertical_size   = library.dimensions.jpk

temperature   = zeros(Float64, zonal_size, meridional_size, vertical_size)
sea_surface_η = zeros(Float64, zonal_size, meridional_size)
bottom_level  = zeros(Int32,   zonal_size, meridional_size)

# Pull the bottom-level index from NEMO once; we use it to mask land cells (`mbkt == 0`) so the heatmaps
# don't paint continents with ocean colors.

get_bottom_level_index!(library, bottom_level)
land_mask = bottom_level .== 0

# ### Initial surface temperature
#
# Read the initial state, mask land, and plot the top layer. ORCA2's tripolar grid is curvilinear, so we
# plot in index space — clearer for a first look than projecting back to lon/lat.

get_temperature!(library, temperature)
surface_temperature = temperature[:, :, 1]
display_temperature = copy(surface_temperature)
display_temperature[land_mask] .= NaN

figure_initial = Figure(size = (820, 380))
axis_initial   = Axis(figure_initial[1, 1]; title  = "Initial surface temperature (°C)",
                                            xlabel = "zonal cell index",
                                            ylabel = "meridional cell index")
heatmap_initial = heatmap!(axis_initial, display_temperature;
                           colormap = :thermal, colorrange = (-2, 30), nan_color = :gray85)
Colorbar(figure_initial[1, 2], heatmap_initial; label = "°C")
figure_initial

# ### Stepping with snapshots
#
# We integrate for `FINAL_ITERATION` time steps and store the sea-surface height anomaly at every step so we
# can animate it afterwards.

sea_surface_η_snapshots  = Vector{Matrix{Float64}}(undef, FINAL_ITERATION)
mean_temperature_history = Float64[]

for iteration in 1:FINAL_ITERATION
    step!(library)
    if mod(iteration, 10) == 0
        get_temperature!(library, temperature)
        get_sea_surface_height!(library, sea_surface_η)

        snapshot                          = copy(sea_surface_η)
        snapshot[land_mask]              .= NaN
        sea_surface_η_snapshots[iteration] = snapshot

        push!(mean_temperature_history, sum(temperature) / length(temperature))

        @info("step",
              iteration = get_iteration_count(library),
              time      = get_simulation_time(library),
              mean_T    = mean_temperature_history[end],
              mean_η    = sum(snapshot[.!land_mask]) / count(.!land_mask))
    end
end

# ### Sea-surface height animation
#
# Build a CairoMakie animation that cycles through the snapshots. The fixed `colorrange` keeps the colorbar
# stable across frames so motion (not rescaling) drives the visible change.

η_minimum = minimum(s -> minimum(filter(!isnan, s)), sea_surface_η_snapshots)
η_maximum = maximum(s -> maximum(filter(!isnan, s)), sea_surface_η_snapshots)
η_range   = max(abs(η_minimum), abs(η_maximum))

snapshot_observable = Observable(sea_surface_η_snapshots[1])

figure_animation = Figure(size = (820, 380))
axis_animation   = Axis(figure_animation[1, 1]; title  = "Sea-surface height (m)",
                                                xlabel = "zonal cell index",
                                                ylabel = "meridional cell index")
heatmap_animation = heatmap!(axis_animation, snapshot_observable;
                             colormap = :balance, colorrange = (-η_range, η_range), nan_color = :gray85)
Colorbar(figure_animation[1, 2], heatmap_animation; label = "m")

animation_filename = "orca2_ice_ssh.mp4"
record(figure_animation, animation_filename, 1:FINAL_ITERATION; framerate = 8) do iteration
    snapshot_observable[] = sea_surface_η_snapshots[iteration]
    axis_animation.title  = "Sea-surface height (m) — step $iteration"
end
nothing #hide

# ```@raw html
# <video controls autoplay loop muted style="max-width:100%">
#   <source src="orca2_ice_ssh.mp4" type="video/mp4">
# </video>
# ```

# ### Mean temperature drift
#
# A one-line diagnostic to confirm the model is doing physics: the global mean temperature over the
# integration should drift slowly because surface forcing redistributes heat.

figure_diagnostic = Figure(size = (640, 300))
axis_diagnostic   = Axis(figure_diagnostic[1, 1]; xlabel = "iteration",
                                                  ylabel = "global mean temperature (°C)",
                                                  title  = "Global-mean temperature drift")
lines!(axis_diagnostic, 1:FINAL_ITERATION, mean_temperature_history; color = :firebrick, linewidth = 2)
figure_diagnostic

# ### Shutdown
#
# [`finalize!`](@ref) closes NEMO's open NetCDF files, calls `mppstop` so MPI (when present) is shut down
# from NEMO's side first, then `dlclose`s the library and cleans up the temporary copy.

finalize!(library)
