@testset "NemoLibrary construction" begin
    library = NemoLibrary("/nonexistent/libnemo.dylib", "/tmp")
    @test library.handle == C_NULL
    @test library.run_directory == "/tmp"
    @test library.library_path == "/nonexistent/libnemo.dylib"
    @test library.initialized == false
    @test library.verbose == true
    @test library.mpi_communicator == Int32(-1)
    @test library.dimensions.jpi == 0

    library_with_mpi = NemoLibrary("/lib.so", "/tmp"; verbose=false, mpi_communicator=42)
    @test library_with_mpi.verbose == false
    @test library_with_mpi.mpi_communicator == Int32(42)
end

@testset "NemoError" begin
    error = NemoError("test message")
    @test error.message == "test message"
    @test sprint(showerror, error) == "NemoError: test message"
end

@testset "NemoConfiguration defaults" begin
    configuration = NemoConfiguration(name="X")
    @test configuration.name == "X"
    @test configuration.mpi == false
    @test isempty(configuration.namelists)
    @test configuration.identifier isa Base.UUID
end
