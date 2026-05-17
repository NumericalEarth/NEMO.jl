module NEMO

using Libdl
using Dates, Printf, UUIDs
using Scratch
using OrderedCollections

const NEMO_VERSION_TARGET = v"4.2.2"

export NemoLibrary, NemoConfiguration, NemoNamelist, NemoError

export initialize!, step!, finalize!
export get_iteration_count, get_simulation_time
export get_timestep, set_timestep!
export get_working_precision

export get_temperature!, set_temperature!
export get_salinity!, set_salinity!
export get_zonal_velocity!, set_zonal_velocity!
export get_meridional_velocity!, set_meridional_velocity!
export get_vertical_velocity!
export get_sea_surface_height!, set_sea_surface_height!

export get_zonal_wind_stress!,      set_zonal_wind_stress!
export get_meridional_wind_stress!, set_meridional_wind_stress!
export get_nonsolar_heat_flux!,     set_nonsolar_heat_flux!
export get_solar_radiation!,        set_solar_radiation!
export get_freshwater_flux!,        set_freshwater_flux!
export get_salt_flux!,              set_salt_flux!

export get_cell_longitude!, get_cell_latitude!
export get_cell_depth!
export get_cell_zonal_size!, get_cell_meridional_size!
export get_bottom_level_index!

export read_namelist, write_namelist
export download_nemo_source, download_orca2_ice_inputs, build_nemo_library
export setup_run_directory, ORCA2_ICE_configuration

include("Types.jl")
include("Source.jl")
include("Build.jl")
include("Namelists.jl")
include("Configurations.jl")
include("RunDirectory.jl")
include("Library.jl")
include("Fields.jl")
include("Forcing.jl")

end # module
