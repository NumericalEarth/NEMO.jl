"""
    nemo_configuration(; source, output_directory, reference, academic = false,
                       name = "NEMO_JULIA_" * reference, namelist_files = ["namelist_cfg"], mpi = false)

Build a [`NemoConfiguration`](@ref) for any NEMO configuration — without needing a dedicated constructor.

* `reference` — the NEMO configuration to derive from: a reference configuration in `cfgs/`
  (e.g. `"GYRE_PISCES"`, `"AMM12"`) by default, or, with `academic = true`, an academic test case in
  `tests/` (e.g. `"VORTEX"`, `"OVERFLOW"`).
* `namelist_files` — the namelist files [`setup_run_directory`](@ref) loads for applying overrides; most
  configurations need only `"namelist_cfg"`, while sea-ice configurations also need `"namelist_ice_cfg"`.
* `my_src` — paths to user Fortran files (or directories of them) copied into the configuration's `MY_SRC`
  at build time. NEMO compiles `MY_SRC` with precedence over the base sources, so this is how custom physics
  or idealized domains are set up: override `usrdef_hgr.F90`, `usrdef_zgr.F90`, `usrdef_istate.F90`,
  `usrdef_sbc.F90`, etc. by supplying same-named files.
* `external_forcing` — when `true`, the surface fluxes are owned by an external driver: NEMO.jl injects a
  no-op `usrdef_sbc.F90` so the momentum, heat, and freshwater fluxes set from Julia (via
  `set_zonal_wind_stress!`, `set_nonsolar_heat_flux!`, …) survive each step instead of being recomputed by
  NEMO, and [`setup_run_directory`](@ref) sets `ln_usr = .true.`. This is the path for forcing a NEMO
  configuration with externally-computed fluxes.

The configuration is created without performing the build; pass it to [`build_nemo_library`](@ref) to
compile it. [`ORCA2_ICE_configuration`](@ref) and [`channel_configuration`](@ref) are thin wrappers around
this constructor with the appropriate `reference`/`academic`/`namelist_files` preset.
"""
function nemo_configuration(; source::AbstractString,
                              output_directory::AbstractString,
                              reference::AbstractString,
                              academic::Bool                 = false,
                              name::AbstractString           = "NEMO_JULIA_" * reference,
                              namelist_files::Vector{String} = ["namelist_cfg"],
                              my_src::Vector{String}         = String[],
                              external_forcing::Bool         = false,
                              mpi::Bool                      = false)
    my_src = copy(my_src)
    external_forcing && push!(my_src, external_forcing_source())
    return NemoConfiguration(
        name                    = name,
        source                  = source,
        output_directory        = output_directory,
        library_path            = joinpath(output_directory, shared_library_filename()),
        run_directory           = joinpath(output_directory, "run"),
        reference_configuration = reference,
        academic                = academic,
        namelist_files          = namelist_files,
        my_src                  = my_src,
        external_forcing        = external_forcing,
        mpi                     = mpi,
    )
end

"""
    external_forcing_source()

Path to the bundled `usrdef_sbc.F90` that hands surface-flux control to an external driver; injected into
`MY_SRC` when a configuration is built with `external_forcing = true`.
"""
external_forcing_source() = joinpath(pkgdir(NEMO), "lib", "usrdef_sbc.F90")

"""
    ORCA2_ICE_configuration(; source, output_directory, name = "NEMO_JULIA_ORCA2_ICE", mpi = false)

Build a [`NemoConfiguration`](@ref) for the ORCA2 + SI3 sea-ice setup (no biogeochemistry), derived from
NEMO's `ORCA2_ICE_PISCES` reference configuration in `cfgs/`.
"""
ORCA2_ICE_configuration(; source::AbstractString,
                          output_directory::AbstractString,
                          name::AbstractString = "NEMO_JULIA_ORCA2_ICE",
                          mpi::Bool            = false) =
    nemo_configuration(; source, output_directory, name, mpi,
                       reference      = "ORCA2_ICE_PISCES",
                       academic       = false,
                       namelist_files = ["namelist_cfg", "namelist_ice_cfg"])

"""
    channel_configuration(; source, output_directory, name = "NEMO_JULIA_CANAL", mpi = false)

Build a [`NemoConfiguration`](@ref) for the re-entrant zonal channel, derived from NEMO's `CANAL` academic
test case in `tests/`. CANAL is an idealized, ocean-only setup (no sea ice, no biogeochemistry) that
generates its own initial state, so — unlike [`ORCA2_ICE_configuration`](@ref) — it needs no downloaded
input files.
"""
channel_configuration(; source::AbstractString,
                        output_directory::AbstractString,
                        name::AbstractString = "NEMO_JULIA_CANAL",
                        mpi::Bool            = false) =
    nemo_configuration(; source, output_directory, name, mpi,
                       reference      = "CANAL",
                       academic       = true,
                       namelist_files = ["namelist_cfg"])
