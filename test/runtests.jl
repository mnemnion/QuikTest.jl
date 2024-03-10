using QuikTest
using Test
using Aqua

@testset "QuikTest.jl" begin
    @testset "Code quality (Aqua.jl)" begin
       # Aqua.test_all(QuikTest)
    end
    # Write your tests here.
    @testset "Spurious failure" begin

        @test_throws ArgumentError throw(ArgumentError("your argument is invalid, opinion discarded"))

    end
end
