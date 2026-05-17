@testset "strip_comment" begin
    @test strip_comment("nn = 1 ! comment")       == "nn = 1 "
    @test strip_comment("! whole line is comment") == ""
    @test strip_comment("plain text")              == "plain text"
end

@testset "parse_scalar_value" begin
    @test parse_scalar_value("12")        === 12
    @test parse_scalar_value("12.5")      === 12.5
    @test parse_scalar_value("1.5d-3")    === 1.5e-3
    @test parse_scalar_value(".true.")    === true
    @test parse_scalar_value(".FALSE.")   === false
    @test parse_scalar_value("\"text\"")  == "text"
    @test parse_scalar_value("'x'")       == "x"
    @test parse_scalar_value("not_a_keyword") == "not_a_keyword"
end

@testset "parse_value with lists" begin
    @test parse_value("1, 2, 3")       == [1, 2, 3]
    @test parse_value("1.0, 2.0, 3.0") == [1.0, 2.0, 3.0]
    @test parse_value("42")            === 42
end

@testset "format_value" begin
    @test format_value(true)     == ".true."
    @test format_value(false)    == ".false."
    @test format_value(42)       == "42"
    @test format_value("hello")  == "\"hello\""
    @test format_value([1, 2, 3]) == "1, 2, 3"
end

@testset "read_namelist round trip" begin
    sample = """
    &namrun
       nn_it000 = 1
       nn_itend = 100
       rn_Dt    = 1200.0
       cn_exp   = "ORCA2"
       ln_rstart = .false.
    /

    &namdom
       jphgr_msh = 0
       ppglam0   = -180.0
       levels    = 1, 2, 3
    /
    """
    path = tempname() * ".namelist"
    write(path, sample)

    namelist = read_namelist(path)
    @test namelist.groups == [:namrun, :namdom]
    @test namelist[:namrun][:nn_it000] === 1
    @test namelist[:namrun][:nn_itend] === 100
    @test namelist[:namrun][:rn_Dt]    === 1200.0
    @test namelist[:namrun][:cn_exp]   == "ORCA2"
    @test namelist[:namrun][:ln_rstart] === false
    @test namelist[:namdom][:levels]   == [1, 2, 3]

    rewritten_path = tempname() * ".namelist"
    write_namelist(rewritten_path, namelist)

    namelist_round_trip = read_namelist(rewritten_path)
    @test namelist_round_trip.groups == namelist.groups
    @test namelist_round_trip[:namrun][:nn_it000] === 1
    @test namelist_round_trip[:namdom][:levels]   == [1, 2, 3]
end
