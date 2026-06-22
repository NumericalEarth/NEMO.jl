module NEMO

using Libdl
using Dates, Printf, UUIDs
using Scratch
using OrderedCollections

const nemo_version_target = v"4.2.2"

export NemoLibrary, NemoConfiguration, NemoNamelist, NemoError

export initialize!, step!, finalize!
export get_iteration_count, get_simulation_time
export get_timestep, set_timestep!
export get_working_precision

# Field and forcing accessors (get_*! / set_*!) are generated from the tables in
# Fields.jl and Forcing.jl, which export them as they are defined.

export read_namelist, write_namelist
export download_nemo_source, download_sette_inputs, download_orca2_ice_inputs, build_nemo_library
export setup_run_directory, clean_run_directory!, stage_inputs!
export nemo_configuration, ORCA2_ICE_configuration, channel_configuration

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
