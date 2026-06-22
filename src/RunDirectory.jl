"""
    stage_inputs!(configuration::NemoConfiguration, inputs)

Copy input files into the configuration's run directory. `inputs` is a collection of paths — files or
directories — typically the `domain_cfg.nc`, bathymetry, and atmospheric forcing a custom configuration
needs. Existing files are overwritten. Returns the run directory.

This is the generic counterpart to `download_orca2_ice_inputs` for configurations that bring their own
inputs; together with [`nemo_configuration`](@ref)'s `my_src` and [`setup_run_directory`](@ref)'s namelist
overrides, it is the path for setting up a custom configuration from Julia.
"""
function stage_inputs!(configuration::NemoConfiguration, inputs)
    mkpath(configuration.run_directory)
    for path in inputs
        ispath(path) || error("Input path not found: $path")
        destination = joinpath(configuration.run_directory, basename(normpath(path)))
        cp(path, destination; force = true, follow_symlinks = true)
    end
    return configuration.run_directory
end

"""
    clean_run_directory!(configuration::NemoConfiguration)

Remove the artifacts a previous NEMO run leaves in the run directory — restarts, diagnostic output files,
the step/date trackers, and the `.output`/`.stat` logs — so the configuration can be re-run in place
without rebuilding. NEMO `ctl_stop`s at initialization when output files from a prior run are present;
this clears them. Namelists, XML I/O definitions, the library, and staged input files (`domain_cfg.nc`,
bathymetry, forcing) are kept. Returns the run directory.
"""
function clean_run_directory!(configuration::NemoConfiguration)
    run_directory = configuration.run_directory
    isdir(run_directory) || return run_directory
    patterns = (r"_restart.*\.nc$", r"_grid_[TUVW].*\.nc$", r"_icemod.*\.nc$", r"_scalar.*\.nc$",
                r"_diaptr.*\.nc$", r"_SBC.*\.nc$", r"^mesh_mask.*\.nc$", r"^run\.stat",
                r"^ocean\.output", r"^output\.namelist", r"^fort\.\d+$", r"^solver\.stat$")
    exact = ("time.step", "date.file", "timing.output", "communication_report.txt",
             "nemo_stdout.log", "layout.dat")
    for entry in readdir(run_directory)
        if entry in exact || any(pattern -> occursin(pattern, entry), patterns)
            rm(joinpath(run_directory, entry); force = true, recursive = true)
        end
    end
    return run_directory
end

"""
    load_namelists!(configuration::NemoConfiguration; filenames)

Read every namelist file from the configuration's run directory into the
`configuration.namelists` dictionary, keyed by filename. Files missing from
disk are silently skipped.
"""
function load_namelists!(configuration::NemoConfiguration;
                         filenames = configuration.namelist_files)
    for filename in filenames
        path = joinpath(configuration.run_directory, filename)
        isfile(path) || continue
        configuration.namelists[filename] = read_namelist(path)
    end
    return configuration
end

"""
    setup_run_directory(configuration::NemoConfiguration; overrides = Dict())

Apply user-supplied namelist overrides to the configuration's run directory.

`overrides` maps `(filename, group, key)` triples to new values, e.g.

```julia
overrides = Dict(
    ("namelist_cfg", :namrun, :nn_itend) => 10,
    ("namelist_cfg", :namdom, :rn_Dt)    => 5400.0,
)
```

Namelists are loaded if not already present, modified in memory, then
written back to disk.

When the configuration was built with `external_forcing = true`, `ln_usr = .true.` and `ln_blk = .false.`
are set in `namsbc` so the externally-provided surface fluxes drive the model.
"""
function setup_run_directory(configuration::NemoConfiguration;
                             overrides::AbstractDict = Dict{Tuple, Any}())
    isempty(configuration.namelists) && load_namelists!(configuration)

    touched_files = Set{String}()
    for ((filename, group, key), value) in overrides
        if !haskey(configuration.namelists, filename)
            error("Namelist file $filename not loaded in this configuration")
        end
        namelist = configuration.namelists[filename]
        if !haskey(namelist, group)
            error("Group $group not found in $filename")
        end
        namelist[group][key] = value
        push!(touched_files, filename)
    end

    configuration.external_forcing && apply_external_forcing_namelist!(configuration, touched_files)

    for filename in touched_files
        write_namelist(joinpath(configuration.run_directory, filename),
                       configuration.namelists[filename])
    end

    return configuration
end

function apply_external_forcing_namelist!(configuration::NemoConfiguration, touched_files::AbstractSet)
    filename = "namelist_cfg"
    haskey(configuration.namelists, filename) || return nothing
    namelist = configuration.namelists[filename]
    applied = false
    for (key, value) in ((:ln_usr, true), (:ln_blk, false))
        if haskey(namelist, :namsbc) && haskey(namelist[:namsbc], key)
            namelist[:namsbc][key] = value
            push!(touched_files, filename)
            applied = true
        end
    end
    applied || @warn "external_forcing is set but namsbc/ln_usr was not found in namelist_cfg; \
                      set ln_usr = .true. manually so the externally-provided fluxes are used"
    return nothing
end
