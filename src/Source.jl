const nemo_repository_url = "https://forge.nemo-ocean.eu/nemo/nemo.git"
const nemo_default_branch = "branch_4.2"

const sette_inputs_url = "https://gws-access.jasmin.ac.uk/public/nemo/sette_inputs"

function nemo_source_cache_directory()
    return @get_scratch!("nemo_source")
end

function nemo_source_path(; version::AbstractString = string(nemo_version_target))
    return joinpath(nemo_source_cache_directory(), "nemo-$version")
end

"""
    download_nemo_source(; version = "$(nemo_version_target)", branch = "$(nemo_default_branch)", force = false)

Clone the NEMO source tree at the given version into a persistent cache
directory and return its path. Subsequent calls return the cached path
without re-cloning unless `force = true`.

A local NEMO source can be used instead by passing it via the `NEMO_SOURCE`
environment variable; in that case this function returns the env-var value
without touching the cache.
"""
function download_nemo_source(; version::AbstractString = string(nemo_version_target),
                                branch::AbstractString  = nemo_default_branch,
                                force::Bool             = false)
    environment_source = get(ENV, "NEMO_SOURCE", "")
    if !isempty(environment_source) && isdir(environment_source)
        return environment_source
    end

    target_path = nemo_source_path(; version)
    if force && isdir(target_path)
        rm(target_path, recursive=true, force=true)
    end
    if isdir(target_path)
        return target_path
    end

    Sys.which("git") === nothing && error("git is required to clone NEMO; set NEMO_SOURCE to a local source tree instead")

    mkpath(dirname(target_path))
    run(`git clone --depth 1 --branch $branch $nemo_repository_url $target_path`)
    return target_path
end


function nemo_inputs_cache_directory()
    return @get_scratch!("nemo_inputs")
end

"""
    download_sette_inputs(name, target_directory; release = "4.2.0", force = false)

Download and extract the SETTE input archive `<name>_v<release>.tar.gz` (bathymetry, mesh,
initial state, and forcing) into `target_directory`. This is the generic entry point for fetching the
inputs of any SETTE-provided configuration — e.g. `"ORCA2_ICE"` or `"AMM12"`. The tarball is cached so
repeated calls only re-extract.

`release` selects which SETTE inputs version to fetch. Pass `force = true` to re-download even if the cache
is populated.
"""
function download_sette_inputs(name::AbstractString,
                               target_directory::AbstractString;
                               release::AbstractString = "4.2.0",
                               force::Bool = false)
    cache = nemo_inputs_cache_directory()
    tarball_name = "$(name)_v$release.tar.gz"
    tarball_path = joinpath(cache, tarball_name)

    if force && isfile(tarball_path)
        rm(tarball_path)
    end
    if !isfile(tarball_path)
        url = "$sette_inputs_url/r$release/$tarball_name"
        @info "Downloading $tarball_name" url
        Sys.which("curl") === nothing && error("curl is required to download NEMO inputs")
        run(`curl -L --fail --progress-bar -o $tarball_path $url`)
    end

    mkpath(target_directory)
    @info "Extracting $tarball_name → $target_directory"
    run(`tar -xzf $tarball_path -C $target_directory --strip-components=1`)
    return target_directory
end

"""
    download_orca2_ice_inputs(target_directory; release = "4.2.0", force = false)

Download and extract the SETTE input archive for ORCA2_ICE (bathymetry, mesh, initial state, CORE-IA
atmospheric forcing) into `target_directory`. Thin wrapper around [`download_sette_inputs`](@ref).
"""
download_orca2_ice_inputs(target_directory::AbstractString; release::AbstractString = "4.2.0",
                          force::Bool = false) =
    download_sette_inputs("ORCA2_ICE", target_directory; release, force)
