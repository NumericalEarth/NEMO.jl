# # [Driving a realistic regional configuration (AMM12) from Julia](@id amm12-example)
#
# This example runs a *realistic* regional ocean configuration that ships with NEMO but has **no dedicated
# constructor** in NEMO.jl — `AMM12`, the Atlantic Margin Model at 12 km resolution over the north-west
# European shelf. It demonstrates the generic path for any NEMO configuration: build it from its reference
# with [`nemo_configuration`](@ref), stage its real input files with [`download_sette_inputs`](@ref), and
# drive it with the same `initialize!` / `step!` / `finalize!` loop used everywhere else.
#
# Contrarily to the idealized [channel](@ref channel-example), AMM12 is forced by real bathymetry, tides,
# lateral open-boundary data, and atmospheric fields — so the sea-surface height carries a genuine tidal
# signal. The setup needs the SETTE input archive (~326 MB), fetched and cached automatically.

using NEMO
using CairoMakie

const output_directory  = get(ENV, "NEMO_OUTPUT", joinpath(homedir(), "nemo_amm12"))
const final_iteration = 240

# ### Source, build, and real inputs
#
# There is no `AMM12_configuration`: we use the generic [`nemo_configuration`](@ref) and just name the
# reference configuration. AMM12 lives in NEMO's `cfgs/`, so this is a `makenemo -r` build (`academic`
# stays `false`). To customize the physics we could pass `my_src = [...]` to override `usrdef_*.F90` or any
# other routine — here we run the configuration as shipped.

source        = download_nemo_source()
configuration = nemo_configuration(source = source, output_directory = output_directory, reference = "AMM12")

build_nemo_library(configuration)

# [`download_sette_inputs`](@ref) fetches `AMM12_v4.2.0.tar.gz` and extracts the bathymetry, mesh, initial
# state, tidal harmonics, open-boundary data, and surface forcing straight into the run directory. The
# tarball is cached, so re-running is fast.

download_sette_inputs("AMM12", configuration.run_directory)

# Limit the run length; `nn_stock` is pushed past the end so no restart is written.

setup_run_directory(configuration; overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend) => final_iteration,
    ("namelist_cfg", :namrun, :nn_stock) => 999999,
))

# ### Loading and initializing

library = NemoLibrary(configuration.library_path, configuration.run_directory; verbose = false)

initialize!(library)

@info "AMM12 grid"        library.dimensions
@info "Working precision" get_working_precision(library)
@info "Initial timestep"  get_timestep(library)

# ### Reading state at every step

zonal_size      = library.dimensions.Nie0 - library.dimensions.Nis0 + 1
meridional_size = library.dimensions.Nje0 - library.dimensions.Njs0 + 1
vertical_size   = library.dimensions.jpk

temperature   = zeros(Float64, zonal_size, meridional_size, vertical_size)
sea_surface_η = zeros(Float64, zonal_size, meridional_size)
bottom_level  = zeros(Int32,   zonal_size, meridional_size)

get_bottom_level_index!(library, bottom_level)
land_mask = bottom_level .== 0

# ### Initial sea-surface temperature over the shelf

get_temperature!(library, temperature)
surface_temperature              = copy(temperature[:, :, 1])
surface_temperature[land_mask]  .= NaN

figure_initial = Figure(size = (760, 560))
axis_initial   = Axis(figure_initial[1, 1]; title  = "AMM12 initial surface temperature (°C)",
                                            xlabel = "zonal cell index",
                                            ylabel = "meridional cell index")
heatmap_initial = heatmap!(axis_initial, surface_temperature;
                           colormap = :thermal, nan_color = :gray85)
Colorbar(figure_initial[1, 2], heatmap_initial; label = "°C")
figure_initial

# ### Stepping — watch the tide in the sea-surface height
#
# We sample the sea-surface height every `snapshot_stride` steps; over a few hundred steps the dominant
# semidiurnal tide sweeps across the shelf.

const snapshot_stride = 8

sea_surface_η_snapshots = Matrix{Float64}[]
iteration_history       = Int[]

for iteration in 1:final_iteration
    step!(library)
    if mod(iteration, snapshot_stride) == 0
        get_sea_surface_height!(library, sea_surface_η)
        snapshot             = copy(sea_surface_η)
        snapshot[land_mask] .= NaN
        push!(sea_surface_η_snapshots, snapshot)
        push!(iteration_history,       iteration)

        @info("step",
              iteration = get_iteration_count(library),
              time      = get_simulation_time(library),
              max_η     = maximum(filter(!isnan, snapshot)))
    end
end

# ### Tidal sea-surface-height animation

η_extreme           = maximum(s -> maximum(abs, filter(!isnan, s)), sea_surface_η_snapshots)
snapshot_observable = Observable(sea_surface_η_snapshots[1])

figure_animation = Figure(size = (760, 560))
axis_animation   = Axis(figure_animation[1, 1]; title  = "AMM12 sea-surface height (m)",
                                                xlabel = "zonal cell index",
                                                ylabel = "meridional cell index")
heatmap_animation = heatmap!(axis_animation, snapshot_observable;
                             colormap = :balance, colorrange = (-η_extreme, η_extreme), nan_color = :gray85)
Colorbar(figure_animation[1, 2], heatmap_animation; label = "m")

animation_filename = "amm12_sea_surface_height.mp4"
record(figure_animation, animation_filename, eachindex(sea_surface_η_snapshots); framerate = 8) do frame
    snapshot_observable[] = sea_surface_η_snapshots[frame]
    axis_animation.title  = "AMM12 sea-surface height (m) — step $(iteration_history[frame])"
end
nothing #hide

# ```@raw html
# <video controls autoplay loop muted style="max-width:100%">
#   <source src="amm12_sea_surface_height.mp4" type="video/mp4">
# </video>
# ```

# ### Shutdown

finalize!(library)
