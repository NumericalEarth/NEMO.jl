function build_script_path()
    return joinpath(pkgdir(NEMO), "lib", "build_nemo_library.sh")
end

function shared_library_filename()
    return Sys.isapple() ? "libnemo.dylib" : "libnemo.so"
end

"""
    build_nemo_library(source, output_directory, configuration_name; mpi = false)

Build NEMO as a shared library by invoking `lib/build_nemo_library.sh`.
Returns the path to the resulting `libnemo.{dylib,so}`. The accompanying
run directory is at `output_directory/run`.

* `source`             — path to a NEMO 4.2.x source tree (use `download_nemo_source()` to fetch one).
* `output_directory`   — destination for build artifacts and run directory.
* `configuration_name` — name for the new configuration in `cfgs/`.
* `mpi`                — build with MPI; `MPI_HOME` is resolved from `mpifort` on `PATH` if unset.
"""
function build_nemo_library(source::AbstractString,
                            output_directory::AbstractString,
                            configuration_name::AbstractString;
                            mpi::Bool = false)
    script_path = build_script_path()
    isfile(script_path) || error("Build script not found: $script_path")

    mkpath(output_directory)

    arguments = String[script_path, source, output_directory, configuration_name]
    mpi && push!(arguments, "--mpi")

    run(Cmd(arguments))

    library_path = joinpath(output_directory, shared_library_filename())
    isfile(library_path) || error("Build completed but $library_path was not produced")

    return library_path
end
