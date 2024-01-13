using QuikTest
using Test
using Aqua

@testset "QuikTest.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(QuikTest)
    end
    # Write your tests here.
end
