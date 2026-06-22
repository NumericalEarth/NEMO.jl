"""
    NemoError(message)

Thrown when NEMO encounters a fatal error. The Fortran `STOP` is intercepted
by the C error handler so the Julia process survives — the captured message
travels back as this exception.
"""
struct NemoError <: Exception
    message :: String
end

Base.showerror(io::IO, error::NemoError) = print(io, "NemoError: ", error.message)


"""
    NemoLibrary(library_path, run_directory; verbose, mpi_communicator)

A loaded NEMO shared library bound to a single run directory. Construct it,
then drive it with `initialize!`, `step!`, `finalize!`.

`mpi_communicator` is the raw integer MPI communicator handle. Pass `-1`
(or `MPI_COMM_NULL` from `MPI.jl` via the extension) to disable MPI.
"""
mutable struct NemoLibrary
    handle             :: Ptr{Nothing}
    library_path       :: String
    temporary_path     :: String
    run_directory      :: String
    dimensions         :: @NamedTuple{jpi::Int, jpj::Int, jpk::Int,
                                      Nis0::Int, Nie0::Int,
                                      Njs0::Int, Nje0::Int}
    working_precision  :: Int
    initialized        :: Bool
    verbose            :: Bool
    mpi_communicator   :: Int32
end

function NemoLibrary(library_path::AbstractString,
                     run_directory::AbstractString;
                     verbose::Bool = true,
                     mpi_communicator::Integer = Int32(-1))
    return NemoLibrary(
        C_NULL,
        abspath(String(library_path)),
        "",
        abspath(String(run_directory)),
        (jpi=0, jpj=0, jpk=0, Nis0=0, Nie0=0, Njs0=0, Nje0=0),
        0,
        false,
        verbose,
        Int32(mpi_communicator),
    )
end

local_zonal_size(lib::NemoLibrary)      = lib.dimensions.Nie0 - lib.dimensions.Nis0 + 1
local_meridional_size(lib::NemoLibrary) = lib.dimensions.Nje0 - lib.dimensions.Njs0 + 1
vertical_size(lib::NemoLibrary)         = lib.dimensions.jpk


"""
    NemoNamelist(groups, parameters)

A Fortran namelist file represented as ordered (group, parameters) pairs.
Each group maps to an `OrderedDict{Symbol, Any}` so insertion order survives
round-trips through `read_namelist` / `write_namelist`.
"""
Base.@kwdef struct NemoNamelist
    groups     :: Vector{Symbol}                       = Symbol[]
    parameters :: Vector{OrderedDict{Symbol, Any}}     = OrderedDict{Symbol, Any}[]
end


"""
    NemoConfiguration(; name, source, output_directory, ...)

Everything needed to build, run, and identify one NEMO configuration: the
source tree it was built from, the resulting library and run directory, the
namelists that drive it, and a UUID so multiple configurations coexist on disk.
"""
Base.@kwdef struct NemoConfiguration
    name                    :: String                       = ""
    source                  :: String                       = ""
    output_directory        :: String                       = ""
    library_path            :: String                       = ""
    run_directory           :: String                       = ""
    reference_configuration :: String                       = "ORCA2_ICE_PISCES"
    academic                :: Bool                          = false
    namelist_files          :: Vector{String}               = ["namelist_cfg"]
    my_src                  :: Vector{String}               = String[]
    external_forcing        :: Bool                          = false
    mpi                     :: Bool                          = false
    namelists               :: Dict{String, NemoNamelist}   = Dict{String, NemoNamelist}()
    identifier              :: UUID                          = uuid4()
end

function Base.show(io::IO, configuration::NemoConfiguration)
    println(io, "NemoConfiguration:")
    println(io, "  name                    = ", configuration.name)
    println(io, "  reference_configuration = ", configuration.reference_configuration)
    println(io, "  academic                = ", configuration.academic)
    println(io, "  mpi                     = ", configuration.mpi)
    println(io, "  source                  = ", configuration.source)
    println(io, "  output_directory        = ", configuration.output_directory)
    println(io, "  library_path            = ", configuration.library_path)
    println(io, "  run_directory           = ", configuration.run_directory)
    println(io, "  namelist_files          = ", configuration.namelist_files)
    println(io, "  my_src                  = ", configuration.my_src)
    println(io, "  external_forcing        = ", configuration.external_forcing)
    println(io, "  namelists               = ", collect(keys(configuration.namelists)))
      print(io, "  identifier              = ", configuration.identifier)
end
