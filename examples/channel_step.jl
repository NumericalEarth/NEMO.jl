# # [Driving a re-entrant channel (CANAL) from Julia](@id channel-example)
#
# This example drives NEMO's `CANAL` academic test case — a re-entrant zonal channel — entirely from Julia.
# Contrarily to the [ORCA2_ICE example](@ref orca2-ice-example), CANAL is an idealized, ocean-only setup: it
# carries no sea ice and no biogeochemistry, and it generates its own initial state, so **no input files need
# to be downloaded**. This makes it the lightest possible end-to-end check that the build/run pipeline is
# general across NEMO configurations, not specialized to ORCA2_ICE.
#
# The only structural difference from the ORCA2_ICE workflow is the configuration constructor:
# [`channel_configuration`](@ref) derives the build from the `CANAL` case in NEMO's `tests/` tree
# (`makenemo -a`) rather than from a reference configuration in `cfgs/` (`makenemo -r`).

using NEMO
using CairoMakie

const output_directory  = get(ENV, "NEMO_OUTPUT", joinpath(homedir(), "nemo_channel"))
const final_iteration = 200

# ### Source, build
#
# [`download_nemo_source`](@ref) shallow-clones NEMO 4.2.x into a `Scratch.jl`-backed cache (cached across
# sessions). [`channel_configuration`](@ref) bundles the build arguments — note `academic = true` and
# `reference_configuration = "CANAL"` are set for us — and [`build_nemo_library`](@ref) compiles it. The
# `key_xios` server is stripped at build time, so Julia reads the state directly without an XML I/O server.

source        = download_nemo_source()
configuration = channel_configuration(source = source, output_directory = output_directory, mpi = false)

build_nemo_library(configuration)

# CANAL ships its own initial state, so we skip the input-download step entirely and only adjust the run
# length. `nn_itend` sets the number of steps; `nn_stock` is pushed past the end so no restart is written.

setup_run_directory(configuration; overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend) => final_iteration,
    ("namelist_cfg", :namrun, :nn_stock) => 999999,
))

# ### Loading and initializing
#
# A [`NemoLibrary`](@ref) ties one shared-library handle to one run directory; `verbose = false` captures
# NEMO's Fortran stdout into `<run_dir>/nemo_stdout.log`.

library = NemoLibrary(configuration.library_path, configuration.run_directory; verbose = false)

initialize!(library)

@info "Grid"              library.dimensions
@info "Working precision" get_working_precision(library)
@info "Initial timestep"  get_timestep(library)

# ### Reading state at every step
#
# Getters return per-rank interior arrays of shape `(Nie0 - Nis0 + 1, Nje0 - Njs0 + 1[, jpk])`. We
# pre-allocate once and reuse the buffers across steps.

zonal_size      = library.dimensions.Nie0 - library.dimensions.Nis0 + 1
meridional_size = library.dimensions.Nje0 - library.dimensions.Njs0 + 1
vertical_size   = library.dimensions.jpk

zonal_velocity      = zeros(Float64, zonal_size, meridional_size, vertical_size)
meridional_velocity = zeros(Float64, zonal_size, meridional_size, vertical_size)
sea_surface_η       = zeros(Float64, zonal_size, meridional_size)
bottom_level        = zeros(Int32,   zonal_size, meridional_size)

get_bottom_level_index!(library, bottom_level)
land_mask = bottom_level .== 0

# ### Stepping with snapshots
#
# We integrate for `final_iteration` steps, sampling the surface speed every `snapshot_stride` steps. Surface
# speed is a robust diagnostic for any ocean configuration — the channel spins up a meandering jet.

const snapshot_stride = 10

speed_snapshots      = Matrix{Float64}[]
iteration_history    = Int[]
mean_speed_history   = Float64[]

for iteration in 1:final_iteration
    step!(library)
    if mod(iteration, snapshot_stride) == 0
        get_zonal_velocity!(library,      zonal_velocity)
        get_meridional_velocity!(library, meridional_velocity)

        surface_speed             = @. sqrt(zonal_velocity[:, :, 1]^2 + meridional_velocity[:, :, 1]^2)
        surface_speed[land_mask] .= NaN
        push!(speed_snapshots,     surface_speed)
        push!(iteration_history,   iteration)
        push!(mean_speed_history,  sum(filter(!isnan, surface_speed)) / count(.!land_mask))

        @info("step",
              iteration = get_iteration_count(library),
              time      = get_simulation_time(library),
              mean_speed = mean_speed_history[end])
    end
end

# ### Surface-speed animation

speed_maximum       = maximum(s -> maximum(filter(!isnan, s)), speed_snapshots)
snapshot_observable = Observable(speed_snapshots[1])

figure_animation = Figure(size = (820, 380))
axis_animation   = Axis(figure_animation[1, 1]; title  = "Surface speed (m/s)",
                                                xlabel = "zonal cell index",
                                                ylabel = "meridional cell index")
heatmap_animation = heatmap!(axis_animation, snapshot_observable;
                             colormap = :speed, colorrange = (0, speed_maximum), nan_color = :gray85)
Colorbar(figure_animation[1, 2], heatmap_animation; label = "m/s")

animation_filename = "channel_surface_speed.mp4"
record(figure_animation, animation_filename, eachindex(speed_snapshots); framerate = 8) do frame
    snapshot_observable[] = speed_snapshots[frame]
    axis_animation.title  = "Surface speed (m/s) — step $(iteration_history[frame])"
end
nothing #hide

# ```@raw html
# <video controls autoplay loop muted style="max-width:100%">
#   <source src="channel_surface_speed.mp4" type="video/mp4">
# </video>
# ```

# ### Shutdown

finalize!(library)
