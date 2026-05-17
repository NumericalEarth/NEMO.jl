"""
    load_namelists!(configuration::NemoConfiguration; filenames)

Read every namelist file from the configuration's run directory into the
`configuration.namelists` dictionary, keyed by filename. Files missing from
disk are silently skipped.
"""
function load_namelists!(configuration::NemoConfiguration;
                         filenames::Tuple = ORCA2_ICE_NAMELIST_FILES)
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

    for filename in touched_files
        write_namelist(joinpath(configuration.run_directory, filename),
                       configuration.namelists[filename])
    end

    return configuration
end
