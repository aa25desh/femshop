#=
The main module for Femshop.
We can reorganize things and make submodules as desired.
=#
module Femshop

# Public macros and functions
export @language, @domain, @mesh, @solver, @stepper, @functionSpace, @trialFunction,
        @testFunction, @nodes, @order, @boundary, @variable, @coefficient, @initial,
        @timeInterval, @weakForm, @LHS, @RHS,
        @outputMesh, @useLog, @finalize
export init_femshop, set_language, dendro, set_solver, set_stepper, add_mesh, output_mesh, add_test_function, 
        add_initial_condition, add_boundary_condition, set_rhs, set_lhs, solve, finalize
export sp_parse
export Variable, add_variable
export Coefficient, add_coefficient

export mass_operator, stiffness_operator

### Module's global variables ###
# config
config = nothing;
prob = nothing;
project_name = "unnamedProject";
output_dir = pwd();
gen_files = nothing;
solver = nothing;
dendro_params = nothing;
#log
use_log = false;
log_file = nothing;
log_line_index = 1;
#mesh
mesh_data = nothing;
grid_data = nothing;
loc2glb = nothing;
refel = nothing;
#problem variables
var_count = 0;
variables = [];
coefficients = [];
#generated functions
genfunc_count = 0;
genfunctions = [];
test_function_symbol = nothing;
#rhs
linears = [];
rhs_params = nothing;
#lhs
bilinears = [];
dt_bilinears = [];
#time stepper
time_stepper = nothing;

include("femshop_includes.jl");
include("macros.jl"); # included here after globals are defined

config = Femshop_config(); # These need to be initialized here
prob = Femshop_prob();

function init_femshop(name="unnamedProject")
    global project_name = name;
    global gen_files = nothing;
    global dendro_params = nothing;
    if log_file != nothing
        close(log_file);
        global use_log = false;
        global log_line_index = 1;
    end
    global mesh_data = nothing;
    global grid_data = nothing;
    global loc2glb = nothing;
    global refel = nothing;
    global var_count = 0;
    global variables = [];
    global coefficients = [];
    global genfunc_count = 0;
    global genfunctions = [];
    global test_function_symbol = nothing;
    global linears = [];
    global bilinears = [];
    global dt_bilinears = [];
    global time_stepper = nothing;
end

function set_language(lang, dirpath, name, head="")
    global output_dir = dirpath;
    global project_name = name;
    global gen_files = CodeGenerator.init_codegenerator(lang, dirpath, name, head);
end

function dendro(;max_depth=6, wavelet_tol=0.1, partition_tol=0.3, solve_tol=1e-6, max_iters=100)
    global dendro_params = (max_depth, wavelet_tol, partition_tol, solve_tol, max_iters);
end

function set_solver(s)
    global solver = s;
end

function set_stepper(type, cfl)
    global time_stepper = Stepper(type, cfl);
    global config.stepper = type;
    log_entry("Set time stepper to "*type);
end

function add_mesh(mesh)
    if typeof(mesh) <: Tuple
        global mesh_data = mesh[1];
        global refel = mesh[2];
        global grid_data = mesh[3]
        global loc2glb = mesh[4];
    else
        global mesh_data = mesh;
    end
    
    log_entry("Added mesh with "*string(mesh_data.nx)*" vertices and "*string(mesh_data.nel)*" elements.");
    log_entry("Full grid has "*string(length(grid_data.allnodes))*" nodes.");
end

function output_mesh(file, format)
    write_mesh(file, format, mesh_data);
    log_entry("Wrote mesh data to file: "*file*".msh");
end

function add_test_function(v)
    global test_function_symbol = v;
    log_entry("Set test function symbol: "*string(v));
end

function add_variable(var)
    global var_count += 1;
    # adjust values arrays
    N = size(grid_data.allnodes)[1];
    if var.type == SCALAR
        var.values = zeros(N);
    elseif var.type == VECTOR
        var.values = zeros(N, config.dimension);
    elseif var.type == TENSOR
        var.values = zeros(N, config.dimension*config.dimension);
    elseif var.type == SYM_TENSOR
        var.values = zeros(N, Int((config.dimension*(config.dimension+1))/2));
    end
    global variables = [variables; var];
    
    global linears = [linears; nothing];
    global bilinears = [bilinears; nothing];
    
    log_entry("Added variable: "*string(var.symbol)*" of type: "*var.type);
end

function add_coefficient(c, val, nfuns)
    global coefficients;
    if typeof(val) <: Array
        vals = [];
        ind = length(genfunctions) - nfuns + 1;
        for i=1:length(val)
            if typeof(val[i]) == String
                push!(vals, genfunctions[ind]);
                ind += 1;
            else
                push!(vals, val[i]);
            end
        end
        push!(coefficients, Coefficient(c, vals));
    else
        if typeof(val) == String
            push!(coefficients, Coefficient(c, [genfunctions[end]]));
        else
            push!(coefficients, Coefficient(c, [val]));
        end
    end
    log_entry("Added coefficient "*string(c)*" : "*string(val));
    
    return coefficients[end];
end

function add_initial_condition(varindex, ex, nfuns)
    global prob;
    while length(prob.initial) < varindex
        prob.initial = [prob.initial; nothing];
    end
    if typeof(ex) <: Array
        vals = [];
        ind = length(genfunctions) - nfuns + 1;
        for i=1:length(ex)
            if typeof(ex[i]) == String
                push!(vals, genfunctions[ind]);
                ind += 1;
            else
                push!(vals, ex[i]);
            end
        end
        prob.initial[varindex] = vals;
    else
        if typeof(ex) == String
            prob.initial[varindex] = genfunctions[end];
        else
            prob.initial[varindex] = ex;
        end
    end
    prob.initial[varindex] = genfunctions[end];
    
    log_entry("Initial condition for "*string(variables[varindex].symbol)*" : "*string(prob.initial[varindex]));
    # hold off on initializing till solve or generate is determined.
end

function add_boundary_condition(var, bid, type, ex, nfuns)
    global prob;
    # make sure the arrays are big enough
    if size(prob.bc_func)[1] < var_count || size(prob.bc_func)[2] < bid
        tmp1 = Array{String,2}(undef, (var_count, bid));
        tmp2 = Array{Any,2}(undef, (var_count, bid));
        tmp3 = zeros(Int, (var_count, bid));
        fill!(tmp1, "");
        fill!(tmp2, GenFunction("","","",0,0));
        tmp1[1:size(prob.bc_func)[1], 1:size(prob.bc_func)[2]] = Base.deepcopy(prob.bc_type);
        tmp2[1:size(prob.bc_func)[1], 1:size(prob.bc_func)[2]] = Base.deepcopy(prob.bc_func);
        tmp3[1:size(prob.bc_func)[1], 1:size(prob.bc_func)[2]] = prob.bid;
        prob.bc_type = tmp1;
        prob.bc_func = tmp2;
        prob.bid = tmp3;
    end
    if typeof(ex) <: Array
        vals = [];
        ind = length(genfunctions) - nfuns + 1;
        for i=1:length(ex)
            if typeof(ex[i]) == String
                push!(vals, genfunctions[ind]);
                ind += 1;
            else
                push!(vals, ex[i]);
            end
        end
        prob.bc_func[var.index, bid] = vals;
    else
        if typeof(ex) == String
            prob.bc_func[var.index, bid] = genfunctions[end];
        else
            prob.bc_func[var.index, bid] = ex;
        end
    end
    prob.bc_type[var.index, bid] = type;
    prob.bid[var.index, bid] = bid;
    
    log_entry("Boundary condition: var="*string(var.symbol)*" bid="*string(bid)*" type="*type*" val="*string(prob.bc_func[var.index, bid]));
end

function set_rhs(var)
    global linears[var.index] = genfunctions[end];
end

function set_lhs(var)
    global bilinears[var.index] = genfunctions[end];
end

function set_dt_lhs(var)
    # lhs_time_derivative signals if the problem is time dependent 
    # and if this variable's eq. will have the form Dt(var) = RHS
    while length(prob.lhs_time_deriv) < var.index
        prob.lhs_time_deriv = [prob.lhs_time_deriv; false];
    end
    prob.lhs_time_deriv[var.index] = true;
    global dt_bilinears[var.index] = Bilinear(genfunctions[end]);
end

function solve(var)
    # Generate files or solve directly
    if gen_files != nothing
        generate_main();
        if dendro_params != nothing
            generate_config(dendro_params);
        else
            generate_config();
        end
        generate_prob();
        generate_mesh();
        generate_genfunction(); 
        generate_bilinear(bilinears[1]);
        generate_linear(linears[1]);
        #generate_stepper();
        generate_output();
    else
        if config.solver_type == CG
            t = @elapsed(init_cgsolver());
            log_entry("Set up CG solver.(took "*string(t)*" seconds)");
            varind = var.index;
            
            lhs = bilinears[varind];
            rhs = linears[varind];
            
            if prob.time_dependent
                global time_stepper = init_stepper(grid_data.allnodes, time_stepper);
                t = @elapsed(var.values = CGSolver.solve(var, lhs, rhs, time_stepper));
                
            else
                t = @elapsed(var.values = CGSolver.solve(var, lhs, rhs));
            end
            
            log_entry("Solved for "*string(var.symbol)*".(took "*string(t)*" seconds)");
        end
    end
    
end

function finalize()
    # Finalize generation
    if gen_files != nothing
        finalize_codegenerator();
    end
    # anything else
    close_log();
    println("Femshop has completed.");
end


end # module
