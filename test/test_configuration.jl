@testset "ORCA2_ICE_configuration" begin
    configuration = ORCA2_ICE_configuration(source = "/some/nemo",
                                            output_directory = "/build")
    @test configuration.name             == "NEMO_JULIA_ORCA2_ICE"
    @test configuration.source           == "/some/nemo"
    @test configuration.output_directory == "/build"
    @test configuration.run_directory    == joinpath("/build", "run")
    @test configuration.library_path     == joinpath("/build", shared_library_filename())
    @test configuration.mpi              == false

    mpi_configuration = ORCA2_ICE_configuration(source           = "/some/nemo",
                                                output_directory = "/build",
                                                mpi              = true)
    @test mpi_configuration.mpi == true
end
