function build_script_path()
    return joinpath(pkgdir(NEMO), "lib", "build_nemo_library.sh")
end

function shared_library_filename()
    return Sys.isapple() ? "libnemo.dylib" : "libnemo.so"
end

"""
    build_nemo_library(source, output_directory, configuration_name;
                       reference = "ORCA2_ICE_PISCES", academic = false, mpi = false)

Build NEMO as a shared library by invoking `lib/build_nemo_library.sh`.
Returns the path to the resulting `libnemo.{dylib,so}`. The accompanying
run directory is at `output_directory/run`.

* `source`             — path to a NEMO 4.2.x source tree (use `download_nemo_source()` to fetch one).
* `output_directory`   — destination for build artifacts and run directory.
* `configuration_name` — name for the new configuration created from `reference`.
* `reference`          — NEMO configuration to derive from: a reference configuration in `cfgs/`
                         (e.g. `"ORCA2_ICE_PISCES"`) or, with `academic = true`, a test case in `tests/`
                         (e.g. `"CANAL"`).
* `academic`           — derive from a `tests/` academic case (`makenemo -a`) instead of a `cfgs/`
                         reference configuration (`makenemo -r`).
* `my_src`             — user Fortran files (or directories of them) copied into the configuration's
                         `MY_SRC` before compilation; NEMO compiles them with precedence over the base
                         sources, which is how custom physics and idealized domains are set up.
* `mpi`                — build with MPI; `MPI_HOME` is resolved from `mpifort` on `PATH` if unset.
"""
function build_nemo_library(source::AbstractString,
                            output_directory::AbstractString,
                            configuration_name::AbstractString;
                            reference::AbstractString = "ORCA2_ICE_PISCES",
                            academic::Bool = false,
                            my_src::AbstractVector{<:AbstractString} = String[],
                            mpi::Bool = false)
    script_path = build_script_path()
    isfile(script_path) || error("Build script not found: $script_path")

    mkpath(output_directory)

    arguments = String[script_path, source, output_directory, configuration_name,
                       "--reference", reference]
    academic && push!(arguments, "--academic")
    for path in my_src
        ispath(path) || error("MY_SRC path not found: $path")
        push!(arguments, "--my-src", abspath(String(path)))
    end
    mpi && push!(arguments, "--mpi")

    run(Cmd(arguments))

    library_path = joinpath(output_directory, shared_library_filename())
    isfile(library_path) || error("Build completed but $library_path was not produced")

    return library_path
end

"""
    build_nemo_library(configuration::NemoConfiguration)

Build the library described by `configuration`, pulling the reference
configuration, academic flag, `MY_SRC` files, and MPI setting from the struct.
"""
build_nemo_library(configuration::NemoConfiguration) =
    build_nemo_library(configuration.source, configuration.output_directory, configuration.name;
                       reference = configuration.reference_configuration,
                       academic  = configuration.academic,
                       my_src    = configuration.my_src,
                       mpi       = configuration.mpi)
