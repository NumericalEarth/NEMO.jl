const ORCA2_ICE_NAMELIST_FILES = (
    "namelist_cfg",
    "namelist_ice_cfg",
)

"""
    ORCA2_ICE_configuration(; source, output_directory, name = "NEMO_JULIA_ORCA2_ICE", mpi = false)

Build a [`NemoConfiguration`](@ref) describing the ORCA2 + SI3 sea-ice setup
(no biogeochemistry). The configuration is created without performing the
build; pass it to [`build_nemo_library`](@ref) to compile it.
"""
function ORCA2_ICE_configuration(; source::AbstractString,
                                   output_directory::AbstractString,
                                   name::AbstractString = "NEMO_JULIA_ORCA2_ICE",
                                   mpi::Bool            = false)
    return NemoConfiguration(
        name             = name,
        source           = source,
        output_directory = output_directory,
        library_path     = joinpath(output_directory, shared_library_filename()),
        run_directory    = joinpath(output_directory, "run"),
        mpi              = mpi,
    )
end
