using PlotlyLight
using JSON3
using Test

@testset "sanity check" begin
    @test Plot(Config(x = 1:10)) isa Plot
    @test Plot(Config(x = 1:10), Config(title="Title")) isa Plot
    @test Plot(Config(x = 1:10), Config(title="Title"), Config(displaylogo=true)) isa Plot
end
@testset "save" begin
    p = Plot()
    PlotlyLight.save(p, "temp.html")
    @test isfile("temp.html")
    rm("temp.html", force=true)
end
