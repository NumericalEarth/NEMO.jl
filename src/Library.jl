function library_symbol(lib::NemoLibrary, name::Symbol)
    lib.handle == C_NULL && error("NEMO library is not loaded")
    return dlsym(lib.handle, name)
end

function with_output_control(work, lib::NemoLibrary)
    lib.verbose && return work()
    log_path     = joinpath(lib.run_directory, "nemo_stdout.log")
    log_file     = open(log_path, "w")
    log_fd       = fd(log_file)
    saved_stdout = ccall(:dup, Cint, (Cint,), 1)
    saved_stderr = ccall(:dup, Cint, (Cint,), 2)
    ccall(:dup2, Cint, (Cint, Cint), log_fd, 1)
    ccall(:dup2, Cint, (Cint, Cint), log_fd, 2)
    try
        return work()
    finally
        ccall(:dup2,  Cint, (Cint, Cint), saved_stdout, 1)
        ccall(:dup2,  Cint, (Cint, Cint), saved_stderr, 2)
        ccall(:close, Cint, (Cint,), saved_stdout)
        ccall(:close, Cint, (Cint,), saved_stderr)
        close(log_file)
    end
end

function in_run_directory(work, lib::NemoLibrary)
    previous_directory = pwd()
    cd(lib.run_directory)
    try
        return work()
    finally
        cd(previous_directory)
    end
end

function retrieve_error_message(lib::NemoLibrary)
    buffer = Vector{UInt8}(undef, 512)
    buffer_length = Ref{Int32}(512)
    ccall(library_symbol(lib, :nemo_get_error_message), Cvoid, (Ptr{UInt8}, Ref{Int32}), buffer, buffer_length)
    return String(buffer[1:buffer_length[]])
end

function load!(lib::NemoLibrary)
    if lib.handle != C_NULL
        dlclose(lib.handle)
        lib.handle = C_NULL
    end
    extension = Sys.isapple() ? ".dylib" : ".so"
    lib.temporary_path = tempname() * extension
    cp(lib.library_path, lib.temporary_path)
    lib.handle = dlopen(lib.temporary_path)
    return lib
end

function unload!(lib::NemoLibrary)
    if lib.handle != C_NULL
        dlclose(lib.handle)
        lib.handle = C_NULL
    end
    if !isempty(lib.temporary_path) && isfile(lib.temporary_path)
        rm(lib.temporary_path, force=true)
        lib.temporary_path = ""
    end
    lib.initialized = false
    return lib
end

function fetch_grid_dimensions(lib::NemoLibrary)
    jpi  = Ref{Int32}(0); jpj  = Ref{Int32}(0); jpk  = Ref{Int32}(0)
    Nis0 = Ref{Int32}(0); Nie0 = Ref{Int32}(0)
    Njs0 = Ref{Int32}(0); Nje0 = Ref{Int32}(0)
    ccall(library_symbol(lib, :nemo_get_grid_size), Cvoid,
          (Ref{Int32}, Ref{Int32}, Ref{Int32},
           Ref{Int32}, Ref{Int32}, Ref{Int32}, Ref{Int32}),
          jpi, jpj, jpk, Nis0, Nie0, Njs0, Nje0)
    return (jpi=Int(jpi[]), jpj=Int(jpj[]), jpk=Int(jpk[]),
            Nis0=Int(Nis0[]), Nie0=Int(Nie0[]),
            Njs0=Int(Njs0[]), Nje0=Int(Nje0[]))
end

function fetch_working_precision(lib::NemoLibrary)
    bytes = Ref{Int32}(0)
    ccall(library_symbol(lib, :nemo_get_working_precision), Cvoid, (Ref{Int32},), bytes)
    return Int(bytes[])
end

"""
    initialize!(lib::NemoLibrary)

Load the shared library, run `nemo_init`, populate grid dimensions and
working precision. Throws `NemoError` if NEMO hits a fatal STOP.
"""
function initialize!(lib::NemoLibrary)
    load!(lib)
    in_run_directory(lib) do
        with_output_control(lib) do
            status = ccall(library_symbol(lib, :nemo_initialize), Cint,
                           (Cint,), lib.mpi_communicator)
            if status != 0
                throw(NemoError("nemo_initialize failed: " * retrieve_error_message(lib)))
            end
        end
        lib.dimensions        = fetch_grid_dimensions(lib)
        lib.working_precision = fetch_working_precision(lib)
        lib.initialized       = true
    end
    return lib
end

"""
    step!(lib::NemoLibrary)

Advance NEMO by one time step. Throws `NemoError` if NEMO hits a fatal STOP.
"""
function step!(lib::NemoLibrary)
    in_run_directory(lib) do
        with_output_control(lib) do
            status = ccall(library_symbol(lib, :nemo_step), Cint, ())
            if status != 0
                throw(NemoError("nemo_step failed: " * retrieve_error_message(lib)))
            end
        end
    end
    return lib
end

"""
    finalize!(lib::NemoLibrary)

Close NEMO files, run timer reports, then unload the shared library.
"""
function finalize!(lib::NemoLibrary)
    if lib.initialized
        in_run_directory(lib) do
            with_output_control(lib) do
                ccall(library_symbol(lib, :nemo_finalize), Cint, ())
            end
        end
    end
    unload!(lib)
    return lib
end

function get_iteration_count(lib::NemoLibrary)
    count = Ref{Int32}(0)
    ccall(library_symbol(lib, :nemo_get_iteration_count), Cvoid, (Ref{Int32},), count)
    return Int(count[])
end

function get_simulation_time(lib::NemoLibrary)
    time = Ref{Float64}(0.0)
    ccall(library_symbol(lib, :nemo_get_simulation_time), Cvoid, (Ref{Float64},), time)
    return time[]
end

function get_timestep(lib::NemoLibrary)
    timestep = Ref{Float64}(0.0)
    ccall(library_symbol(lib, :nemo_get_timestep), Cvoid, (Ref{Float64},), timestep)
    return timestep[]
end

function set_timestep!(lib::NemoLibrary, timestep::Real)
    ccall(library_symbol(lib, :nemo_set_timestep), Cvoid, (Float64,), Float64(timestep))
    return lib
end

function get_working_precision(lib::NemoLibrary)
    return lib.working_precision
end
