#=
# Test out different node orderings
=#
if !@isdefined(Femshop)
    @everywhere include("../Femshop.jl");
    @everywhere using .Femshop
end

@everywhere include("multi-setup.jl")

println("Six DOF per node, averaged "*string(times)*" times")

@everywhere include("multi-hilb.jl")
@everywhere include("multi-lex.jl")
@everywhere include("multi-rand.jl")

using Plots
pyplot();
labels = ["Hilbert", "Lex.", "Random"];
display(bar(labels, timings, legend=false, reuse=false))

@finalize()
