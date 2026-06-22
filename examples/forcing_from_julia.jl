# # [Forcing NEMO with externally-computed fluxes](@id external-forcing-example)
#
# This example drives a NEMO channel with surface fluxes **computed in Julia and pushed into NEMO at every
# step**, rather than by NEMO's own bulk formula or analytic forcing. This is the mechanism a coupler — for
# instance a future NumericalEarth NEMO component — uses to force NEMO with its own air–sea fluxes: compute
# the wind stress, heat, and freshwater fluxes on NEMO's grid, and hand them over.
#
# The enabling switch is `external_forcing = true` on [`nemo_configuration`](@ref). It injects a no-op
# `usrdef_sbc.F90` into `MY_SRC` so NEMO keeps the fluxes set from Julia instead of recomputing them, and
# [`setup_run_directory`](@ref) sets `ln_usr = .true.`. The forcing setters then write straight into NEMO's
# surface-flux arrays:
#
# | quantity            | setter                          |
# |---------------------|---------------------------------|
# | zonal wind stress   | [`set_zonal_wind_stress!`](@ref)      |
# | meridional stress   | [`set_meridional_wind_stress!`](@ref) |
# | non-solar heat flux | [`set_nonsolar_heat_flux!`](@ref)     |
# | solar radiation     | [`set_solar_radiation!`](@ref)        |
# | freshwater flux     | [`set_freshwater_flux!`](@ref)        |
#
# Here the forcing is a simple analytic wind computed on NEMO's own latitudes — a stand-in for the fluxes a
# coupler would compute or interpolate from reanalysis.

using NEMO
using CairoMakie

const output_directory  = get(ENV, "NEMO_OUTPUT", joinpath(homedir(), "nemo_external_forcing"))
const final_iteration = 5000

# ### Build the channel with external forcing enabled

source        = download_nemo_source()
configuration = nemo_configuration(source = source, output_directory = output_directory,
                                   reference = "CANAL", academic = true,
                                   name = "NEMO_JULIA_CANAL_FORCED",   # distinct from the plain channel example
                                   external_forcing = true)

build_nemo_library(configuration)

setup_run_directory(configuration; overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend) => final_iteration,
    ("namelist_cfg", :namrun, :nn_stock) => 999999,
))

library = NemoLibrary(configuration.library_path, configuration.run_directory; verbose = false)
initialize!(library)

zonal_size      = library.dimensions.Nie0 - library.dimensions.Nis0 + 1
meridional_size = library.dimensions.Nje0 - library.dimensions.Njs0 + 1
vertical_size   = library.dimensions.jpk

# ### A time-varying forcing, computed live in Julia
#
# The forcing lives entirely in Julia and changes with time — nothing is precomputed or written to disk. We
# read NEMO's cell latitudes once, for spatial structure, and then at every step compute the wind stress
# from the model clock, [`get_simulation_time`](@ref). Here an idealized zonal wind oscillates over a
# one-day period with a mid-channel envelope; a real coupler would instead evaluate time-dependent air–sea
# fluxes on this same grid.

const wind_stress_amplitude = 0.2        # N m⁻²
const forcing_period        = 86400.0    # s (one day)

latitude          = zeros(Float64, zonal_size, meridional_size)
get_cell_latitude!(library, latitude)
latitude_envelope = @. cos(π * latitude / 20)

zonal_wind_stress = zeros(Float64, zonal_size, meridional_size)
meridional_stress = zeros(Float64, zonal_size, meridional_size)

# ### Step, recomputing and pushing the forcing each iteration
#
# Every step we evaluate the wind stress at the current model time, hand it to NEMO, and read back the
# surface speed. The current spins up and reverses with the oscillating wind — driven entirely by the
# live Julia-side fields.

zonal_velocity      = zeros(Float64, zonal_size, meridional_size, vertical_size)
meridional_velocity = zeros(Float64, zonal_size, meridional_size, vertical_size)
bottom_level        = zeros(Int32,   zonal_size, meridional_size)
get_bottom_level_index!(library, bottom_level)
land_mask = bottom_level .== 0

const snapshot_stride = 6
speed_snapshots   = Matrix{Float64}[]
iteration_history = Int[]

for iteration in 1:final_iteration
    time = get_simulation_time(library)
    @. zonal_wind_stress = wind_stress_amplitude * sin(2π * time / forcing_period) * latitude_envelope
    set_zonal_wind_stress!(library,      zonal_wind_stress)
    set_meridional_wind_stress!(library, meridional_stress)

    step!(library)

    if mod(iteration, snapshot_stride) == 0
        get_zonal_velocity!(library,      zonal_velocity)
        get_meridional_velocity!(library, meridional_velocity)
        surface_speed             = @. sqrt(zonal_velocity[:, :, 1]^2 + meridional_velocity[:, :, 1]^2)
        surface_speed[land_mask] .= NaN
        push!(speed_snapshots,   surface_speed)
        push!(iteration_history, iteration)

        @info("step",
              iteration  = get_iteration_count(library),
              time       = get_simulation_time(library),
              mean_speed = sum(filter(!isnan, surface_speed)) / count(.!land_mask))
    end
end

# ### Surface-speed animation

speed_maximum       = maximum(s -> maximum(filter(!isnan, s)), speed_snapshots)
snapshot_observable = Observable(speed_snapshots[1])

figure_animation = Figure(size = (820, 380))
axis_animation   = Axis(figure_animation[1, 1]; title  = "Wind-driven surface speed (m/s)",
                                                xlabel = "zonal cell index",
                                                ylabel = "meridional cell index")
heatmap_animation = heatmap!(axis_animation, snapshot_observable;
                             colormap = :speed, colorrange = (0, speed_maximum), nan_color = :gray85)
Colorbar(figure_animation[1, 2], heatmap_animation; label = "m/s")

animation_filename = "external_forcing_surface_speed.mp4"
record(figure_animation, animation_filename, eachindex(speed_snapshots); framerate = 8) do frame
    snapshot_observable[] = speed_snapshots[frame]
    axis_animation.title  = "Wind-driven surface speed (m/s) — step $(iteration_history[frame])"
end
nothing #hide

# ```@raw html
# <video controls autoplay loop muted style="max-width:100%">
#   <source src="external_forcing_surface_speed.mp4" type="video/mp4">
# </video>
# ```

finalize!(library)
