#=
# DG solver
=#
module DGSolver

export init_dgsolver, solve, nonlinear_solve

import ..Femshop: JULIA, CPP, MATLAB, DENDRO, HOMG, CUSTOM_GEN_TARGET,
            SQUARE, IRREGULAR, UNIFORM_GRID, TREE, UNSTRUCTURED, 
            CG, DG, HDG,
            NODAL, MODAL, LEGENDRE, UNIFORM, GAUSS, LOBATTO, 
            NONLINEAR_NEWTON, NONLINEAR_SOMETHING, 
            EULER_EXPLICIT, EULER_IMPLICIT, CRANK_NICHOLSON, RK4, LSRK4, ABM4, 
            DEFAULT_SOLVER, PETSC, 
            VTK, RAW_OUTPUT, CUSTOM_OUTPUT, 
            DIRICHLET, NEUMANN, ROBIN, NO_BC,
            MSH_V2, MSH_V4,
            SCALAR, VECTOR, TENSOR, SYM_TENSOR,
            LHS, RHS,
            LINEMESH, QUADMESH, HEXMESH
import ..Femshop: log_entry, printerr
import ..Femshop: config, prob, variables, mesh_data, grid_data, refel, time_stepper, elemental_order
import ..Femshop: Variable, Coefficient, GenFunction, Jacobian
import ..Femshop: geometric_factors, geometric_factors_face, build_deriv_matrix, build_face_deriv_matrix, build_refel

using LinearAlgebra, SparseArrays

include("cg_boundary.jl"); # Can we use the CG versions here? 
include("nonlinear.jl");
include("cg_matrixfree.jl");
include("face_data.jl");
#include("dg_utils.jl");
#include("desired.jl");

function init_dgsolver()
    dim = config.dimension;

    # build initial conditions
    for vind=1:length(variables)
        if vind <= length(prob.initial)
            if prob.initial[vind] != nothing
                variables[vind].values = zeros(size(variables[vind].values));
                # Set initial condition
                if typeof(prob.initial[vind]) <: Array
                    for ci=1:length(prob.initial[vind])
                        for ni=1:size(grid_data.allnodes,2)
                            if dim == 1
                                variables[vind].values[ci,ni] = prob.initial[vind][ci].func(grid_data.allnodes[ni],0,0,0);
                            elseif dim == 2
                                variables[vind].values[ci,ni] = prob.initial[vind][ci].func(grid_data.allnodes[1,ni],grid_data.allnodes[2,ni],0,0);
                            elseif dim == 3
                                variables[vind].values[ci,ni] = prob.initial[vind][ci].func(grid_data.allnodes[1,ni],grid_data.allnodes[2,ni],grid_data.allnodes[3,ni],0);
                            end
                        end
                    end
                else
                    for ni=1:size(grid_data.allnodes,2)
                        if dim == 1
                            variables[vind].values[ni] = prob.initial[vind].func(grid_data.allnodes[ni],0,0,0);
                        elseif dim == 2
                            variables[vind].values[ni] = prob.initial[vind].func(grid_data.allnodes[1,ni],grid_data.allnodes[2,ni],0,0);
                        elseif dim == 3
                            variables[vind].values[ni] = prob.initial[vind].func(grid_data.allnodes[1,ni],grid_data.allnodes[2,ni],grid_data.allnodes[3,ni],0);
                        end
                    end
                end

                variables[vind].ready = true;
                log_entry("Built initial conditions for: "*string(variables[vind].symbol));
            end
        end
    end
end

function linear_solve(var, bilinear, linear, face_bilinear, face_linear, stepper=nothing)
    if config.dimension > 2
        printerr("DG solver only available for 1D and 2D. Surface quadrature under construction.")
        #return;
    end
    
    if config.linalg_matrixfree
        return solve_matrix_free_sym(var, bilinear, linear, stepper);
        #return solve_matrix_free_asym(var, bilinear, linear, stepper);
    end
    if prob.time_dependent && !(stepper === nothing)
        #TODO time dependent coefficients
        assemble_t = @elapsed((A, b) = assemble(var, bilinear, linear, face_bilinear, face_linear, 0, stepper.dt));
        global Amat = A;
        global bvec = b;
        log_entry("Assembly took "*string(assemble_t)*" seconds");

        log_entry("Beginning "*string(stepper.Nsteps)*" time steps.");
        t = 0;
        sol = [];
        start_t = Base.Libc.time();
        for i=1:stepper.Nsteps
            stupidjulia=sol;
            if stepper.stages > 1
                resu = zeros(size(b));
                for rki=1:stepper.stages
                    rktime = t + stepper.c[rki]*stepper.dt;
                    b = assemble_rhs_only(var, linear, face_linear, rktime, stepper.dt);
                    sol = A\b;
                    resu = stepper.a[rki].*resu + sol;
                    place_sol_in_vars(var, stepper.b[rki].*resu, stepper);
                end
            else
                b = assemble_rhs_only(var, linear, face_linear, t, stepper.dt);
                sol = A\b;
                
                place_sol_in_vars(var, sol, stepper);
            end
            
            #println("b(bdry): "*string(b[1])*", "*string(b[end]));
            
            t += stepper.dt;
        end
        end_t = Base.Libc.time();

        log_entry("Solve took "*string(end_t-start_t)*" seconds");
        #display(sol);
		# outfile = "linear_sol.txt"
		# open(outfile, "w") do f
  		# 	for ii in sol
    	# 		println(f, ii)
  		# 	end
		# end # the file f is automatically closed after this block finishes
        return sol;

    else
        assemble_t = @elapsed((A, b) = assemble(var, bilinear, linear, face_bilinear, face_linear));
        # uncomment to look at A
        global Amat = A;
        
        sol_t = @elapsed(sol = A\b);
        
        log_entry("Assembly took "*string(assemble_t)*" seconds");
        log_entry("Linear solve took "*string(sol_t)*" seconds");
        #display(A);
        #display(b);
        #display(sol);
        return sol;
    end
end

function nonlinear_solve(var, nlvar, bilinear, linear, stepper=nothing)
    if prob.time_dependent && !(stepper === nothing)
        #TODO time dependent coefficients
        
        log_entry("Beginning "*string(stepper.Nsteps)*" time steps.");
        t = 0;
        start_t = Base.Libc.time();
        nl = nonlinear(100, 1e-9, 1e-9);
        init_nonlinear(nl, var, nlvar, bilinear, linear);
        for i=1:stepper.Nsteps
			println("solve for time step ", i);
			newton(nl, assemble, assemble_rhs_only, nlvar, t, stepper.dt);
            t += stepper.dt;
			nlvar[4].values = copy(nlvar[1].values);
			nlvar[5].values = copy(nlvar[2].values);
			if (i % 10 ==0)
				outfile = string("LD_u_",i);
				open(outfile, "w") do f
					for ii=1:length(nlvar[1].values)
						println(f, nlvar[1].values[ii])
					end
					close(f)
				end
				outfile = string("LD_v_",i);
				open(outfile, "w") do f
					for ii=1:length(nlvar[2].values)
						println(f, nlvar[2].values[ii])
					end
					close(f)
				end
			end
        end
        end_t = Base.Libc.time();

        log_entry("Solve took "*string(end_t-start_t)*" seconds");
        #display(sol);
        #return nlvar.values;
        return [];

    else
        start_t = Base.Libc.time();
        nl = nonlinear(100, 1e-12, 1e-12);
        init_nonlinear(nl, var, nlvar, bilinear, linear);
        newton(nl, assemble, assemble_rhs_only, nlvar);
        end_t = Base.Libc.time();

        log_entry("Solve took "*string(end_t-start_t)*" seconds");
        
        #return nlvar.values;
        return [];
    end
end

# ########################
# # tmp for testing
function the_desired(args)
    
end
# #########################

# assembles the A and b in Au=b
function assemble(var, bilinear, linear, face_bilinear, face_linear, t=0.0, dt=0.0)
    Np = refel.Np;
    nel = mesh_data.nel;
    N1 = size(grid_data.allnodes,2);
    multivar = typeof(var) <: Array;
    maxvarindex = 0;
    if multivar
        # multiple variables being solved for simultaneously
        dofs_per_node = 0;
        var_to_dofs = [];
        for vi=1:length(var)
            tmp = dofs_per_node;
            dofs_per_node += length(var[vi].symvar.vals);
            push!(var_to_dofs, (tmp+1):dofs_per_node);
            maxvarindex = max(maxvarindex,var[vi].index);
        end
    else
        # one variable
        dofs_per_node = length(var.symvar.vals);
        maxvarindex = var.index;
    end
    Nn = dofs_per_node * N1;

    b = zeros(Nn);
    #A = spzeros(Nn, Nn);
    AI = zeros(Int, nel*dofs_per_node*Np*dofs_per_node*Np);
    AJ = zeros(Int, nel*dofs_per_node*Np*dofs_per_node*Np);
    AV = zeros(nel*dofs_per_node*Np*dofs_per_node*Np);
    
    # Stiffness and mass are precomputed for uniform grid meshes
    if config.mesh_type == UNIFORM_GRID && config.geometry == SQUARE
        glb = grid_data.loc2glb[:,1];
        xe = grid_data.allnodes[:,glb[:]];
        (detJ, J) = geometric_factors(refel, xe);
        wgdetj = refel.wg .* detJ;
        if config.dimension == 1
            (RQ1, RD1) = build_deriv_matrix(refel, J);
            TRQ1 = RQ1';
            stiffness = [(TRQ1 * diagm(wgdetj) * RQ1)];
        elseif config.dimension == 2
            (RQ1, RQ2, RD1, RD2) = build_deriv_matrix(refel, J);
            (TRQ1, TRQ2) = (RQ1', RQ2');
            stiffness = [(TRQ1 * diagm(wgdetj) * RQ1) , (TRQ2 * diagm(wgdetj) * RQ2)];
        else
            (RQ1, RQ2, RQ3, RD1, RD2, RD3) = build_deriv_matrix(refel, J);
            (TRQ1, TRQ2, TRQ3) = (RQ1', RQ2', RQ3');
            stiffness = [(TRQ1 * diagm(wgdetj) * RQ1) , (TRQ2 * diagm(wgdetj) * RQ2) , (TRQ3 * diagm(wgdetj) * RQ3)];
        end
        mass = (refel.Q)' * diagm(wgdetj) * refel.Q;
    else
        stiffness = 0;
        mass = 0;
    end
    
    vol_J = Array{Jacobian,1}(undef,nel);
    
    loop_time = Base.Libc.time();
    # Elemental loop follows elemental ordering
    for ei=1:nel
        e = elemental_order[ei];
        glb = grid_data.loc2glb[:,e];           # global indices of this element's nodes for extracting values from var arrays
        xe = grid_data.allnodes[:,glb[:]];      # coordinates of this element's nodes for evaluating coefficient functions
        
        (detJ, J) = geometric_factors(refel, xe);
        vol_J[ei] = J;
        
        Astart = (e-1)*Np*dofs_per_node*Np*dofs_per_node + 1; # The segment of AI, AJ, AV for this element
        
        # The linear part. Compute the elemental linear part for each dof
        rhsargs = (var, xe, glb, refel, RHS, t, dt, stiffness, mass);
        lhsargs = (var, xe, glb, refel, LHS, t, dt, stiffness, mass);
        if dofs_per_node == 1
            linchunk = linear.func(rhsargs);  # get the elemental linear part
            b[glb] .+= linchunk;

            bilinchunk = bilinear.func(lhsargs); # the elemental bilinear part
            #A[glb, glb] .+= bilinchunk;         # This will be very inefficient for sparse A
            for jj=1:Np
                offset = Astart - 1 + (jj-1)*Np;
                for ii=1:Np
                    AI[offset + ii] = glb[ii];
                    AJ[offset + ii] = glb[jj];
                    AV[offset + ii] = bilinchunk[ii, jj];
                end
            end
            
        elseif typeof(var) == Variable
            # only one variable, but more than one dof
            linchunk = linear.func(rhsargs);
            insert_linear!(b, linchunk, glb, 1:dofs_per_node, dofs_per_node);

            bilinchunk = bilinear.func(lhsargs);
            insert_bilinear!(AI, AJ, AV, Astart, bilinchunk, glb, 1:dofs_per_node, dofs_per_node);
        else
            linchunk = linear.func(rhsargs);
            insert_linear!(b, linchunk, glb, 1:dofs_per_node, dofs_per_node);

            bilinchunk = bilinear.func(lhsargs);
            insert_bilinear!(AI, AJ, AV, Astart, bilinchunk, glb, 1:dofs_per_node, dofs_per_node);
        end
    end
    
    # surface assembly for dg
    if !(face_linear===nothing || face_bilinear===nothing)
        # dim2face = [0,2,4,6];
        # frefel = build_refel(refel.dim-1, refel.N, dim2face[refel.dim], config.elemental_nodes);
        
        for fid = 1:size(grid_data.face2glb,3)
            
            frefelind = [grid_data.faceRefelInd[1,fid], grid_data.faceRefelInd[2,fid]]; # refel based index of face in both elements
            
            face2glb = grid_data.face2glb[:,:,fid]; # local to global for face
            if frefelind[2] > 0 # not a boundary face
                flocal = [refel.face2local[frefelind[1]], refel.face2local[frefelind[2]]]; # local indices of face in both elements
            else # a boundary face
                face2glb[:,2] = face2glb[:,1]; # same global index for inside and out
                frefelind[2] = frefelind[1];
                flocal = [refel.face2local[frefelind[1]], refel.face2local[frefelind[1]]]; # local indices of face in both elements
            end
            
            facenodes = grid_data.allnodes[:,face2glb[:,1]]; # coordinates of this face's nodes for evaluating coefficient functions
            
            normal = grid_data.facenormals[:,fid]; # normal vector
            
            faceBID = mesh_data.bdryID[fid]; # BID of face (0 for interior)
            
            (fdetJ, fJ) = geometric_factors_face(refel, frefelind[1], facenodes); # compute geometric factors here for the face
            #fdetJ = [1];
            #fJ = [1];
            
            e1 = mesh_data.face2element[1,fid]; # element on side 1
            e2 = mesh_data.face2element[2,fid]; # and 2
            if e1==0 # boundary
                e1=e2;
            end
            if e2==0 # boundary
                e2=e1;
            end
            vol_J1 = vol_J[e1]; # volume gepmetric factors for e1
            vol_J2 = vol_J[e2]; # and e2
            
            loc2glb = [grid_data.loc2glb[:,e1], grid_data.loc2glb[:,e2]]; # volume local to global
            
            face_wgdetj = refel.surf_wg[1] .* fdetJ;
            #println("face "*string(fid)*" fdetJ "*string(fdetJ)*" wgdetj "*string(face_wgdetj));
            
            rhsargs = (var, refel, loc2glb, fid, frefelind, facenodes, face2glb, normal, faceBID, fdetJ, fJ, vol_J1, vol_J2, face_wgdetj, RHS, t, dt);
            lhsargs = (var, refel, loc2glb, fid, frefelind, facenodes, face2glb, normal, faceBID, fdetJ, fJ, vol_J1, vol_J2, face_wgdetj, LHS, t, dt);
            
            if dofs_per_node == 1
                linchunk = face_linear.func(rhsargs);  # get the elemental linear part
                #linchunk = the_desired(rhsargs);
                linchunk[1] = linchunk[1][flocal[1]];
                linchunk[2] = linchunk[2][flocal[2]];
                if faceBID == 0
                    b[face2glb[:,1]] .+= linchunk[1];
                    b[face2glb[:,2]] .+= linchunk[2];
                elseif mesh_data.face2element[1,fid] == 0
                    b[face2glb[:,2]] .+= linchunk[2];
                else
                    b[face2glb[:,1]] .+= linchunk[1];
                end
                
    
                bilinchunk = face_bilinear.func(lhsargs); # the elemental bilinear part
                
                if typeof(bilinchunk[1]) <: Number
                    bilinchunk = [[bilinchunk[1]], [bilinchunk[2]], [bilinchunk[3]], [bilinchunk[4]]];
                else
                    bilinchunk[1] = bilinchunk[1][flocal[1],flocal[1]];
                    bilinchunk[2] = bilinchunk[2][flocal[1],flocal[2]];
                    bilinchunk[3] = bilinchunk[3][flocal[2],flocal[1]];
                    bilinchunk[4] = bilinchunk[4][flocal[2],flocal[2]];
                end
                #bilinchunk = temporary_lhs_func(lhsargs);
                #println(bilinchunk)
                nfp = size(face2glb,1);
                for jj=1:nfp
                    append!(AI, face2glb[:,1]);
                    append!(AJ, face2glb[jj,1]*ones(Int, nfp));
                    append!(AV, bilinchunk[1][:,jj]);
                    
                    append!(AI, face2glb[:,1]);
                    append!(AJ, face2glb[jj,2]*ones(Int, nfp));
                    append!(AV, bilinchunk[2][:,jj]);
                    
                    append!(AI, face2glb[:,2]);
                    append!(AJ, face2glb[jj,1]*ones(Int, nfp));
                    append!(AV, bilinchunk[3][:,jj]);
                    
                    append!(AI, face2glb[:,2]);
                    append!(AJ, face2glb[jj,2]*ones(Int, nfp));
                    append!(AV, bilinchunk[4][:,jj]);
                end
            end	 	
        end
    end
    
    loop_time = Base.Libc.time() - loop_time;
    
    # Build the sparse A. Uses default + to combine overlaps
    A = sparse(AI, AJ, AV);
    
    # Boundary conditions
    bc_time = Base.Libc.time();
    bidcount = length(grid_data.bids); # the number of BIDs
    dirichlet_rows = zeros(0);
    neumann_rows = zeros(0);
    neumann_Is = zeros(Int,0);
    neumann_Js = zeros(Int,0);
    neumann_Vs = zeros(0);
    if dofs_per_node > 1
        if multivar
            dofind = 0;
            for vi=1:length(var)
                for compo=1:length(var[vi].symvar.vals)
                    dofind = dofind + 1;
                    for bid=1:bidcount
                        if prob.bc_type[var[vi].index, bid] == DIRICHLET
                            #(A, b) = dirichlet_bc(A, b, prob.bc_func[var[vi].index, bid][compo], grid_data.bdry[bid], t, dofind, dofs_per_node);
                            (tmprows, b) = dirichlet_bc(A, b, prob.bc_func[var[vi].index, bid][compo], grid_data.bdry[bid], t, dofind, dofs_per_node);
                            append!(dirichlet_rows, tmprows);
                        elseif prob.bc_type[var[vi].index, bid] == NEUMANN
                            #(A, b) = neumann_bc(A, b, prob.bc_func[var[vi].index, bid][compo], grid_data.bdry[bid], bid, t, dofind, dofs_per_node);
                            (tmprows, tmpIs, tmpJs, tmpVs, b) = neumann_bc(A, b, prob.bc_func[var[vi].index, bid][compo], grid_data.bdry[bid], bid, t, dofind, dofs_per_node);
                            append!(neumann_rows, tmprows);
                            append!(neumann_Is, tmpIs);
                            append!(neumann_Js, tmpJs);
                            append!(neumann_Vs, tmpVs);
                        elseif prob.bc_type[var[vi].index, bid] == ROBIN
                            printerr("Robin BCs not ready.");
                        elseif prob.bc_type[var[vi].index, bid] == NO_BC
                            # do nothing
                        else
                            printerr("Unsupported boundary condition type: "*prob.bc_type[var[vi].index, bid]);
                        end
                    end
                end
            end
        else
            for d=1:dofs_per_node
                dofind = d;
                for bid=1:bidcount
                    if prob.bc_type[var.index, bid] == DIRICHLET
                        #(A, b) = dirichlet_bc(A, b, prob.bc_func[var.index, bid][d], grid_data.bdry[bid], t, dofind, dofs_per_node);
                        (tmprows, b) = dirichlet_bc(A, b, prob.bc_func[var.index, bid][d], grid_data.bdry[bid], t, dofind, dofs_per_node);
                        append!(dirichlet_rows, tmprows);
                    elseif prob.bc_type[var.index, bid] == NEUMANN
                        #(A, b) = neumann_bc(A, b, prob.bc_func[var.index, bid][d], grid_data.bdry[bid], bid, t, dofind, dofs_per_node);
                        (tmprows, tmpIs, tmpJs, tmpVs, b) = neumann_bc(A, b, prob.bc_func[var.index, bid][compo], grid_data.bdry[bid], bid, t, dofind, dofs_per_node);
                        append!(neumann_rows, tmprows);
                        append!(neumann_Is, tmpIs);
                        append!(neumann_Js, tmpJs);
                        append!(neumann_Vs, tmpVs);
                    elseif prob.bc_type[var.index, bid] == ROBIN
                        printerr("Robin BCs not ready.");
                    elseif prob.bc_type[var.index, bid] == NO_BC
                        # do nothing
                    else
                        printerr("Unsupported boundary condition type: "*prob.bc_type[var.index, bid]);
                    end
                end
            end
        end
    else
        for bid=1:bidcount
            if prob.bc_type[var.index, bid] == DIRICHLET
                #(A, b) = dirichlet_bc(A, b, prob.bc_func[var.index, bid][1], grid_data.bdry[bid], t);
                (tmprows, b) = dirichlet_bc(A, b, prob.bc_func[var.index, bid][1], grid_data.bdry[bid], t);
                append!(dirichlet_rows, tmprows);
            elseif prob.bc_type[var.index, bid] == NEUMANN
                #(A, b) = neumann_bc(A, b, prob.bc_func[var.index, bid][1], grid_data.bdry[bid], bid, t);
                (tmprows, tmpIs, tmpJs, tmpVs, b) = neumann_bc(A, b, prob.bc_func[var.index, bid][1], grid_data.bdry[bid], bid, t);
                append!(neumann_rows, tmprows);
                append!(neumann_Is, tmpIs);
                append!(neumann_Js, tmpJs);
                append!(neumann_Vs, tmpVs);
            elseif prob.bc_type[var.index, bid] == ROBIN
                printerr("Robin BCs not ready.");
            elseif prob.bc_type[var.index, bid] == NO_BC
                # do nothing
            else
                printerr("Unsupported boundary condition type: "*prob.bc_type[var.index, bid]);
            end
        end
    end
    
    if length(dirichlet_rows)>0
        A = identity_rows(A, dirichlet_rows, length(b));
    end
    if length(neumann_rows)>0
        A = insert_sparse_rows(A, neumann_Is, neumann_Js, neumann_Vs);
    end
    
    # Reference points
    if size(prob.ref_point,1) >= maxvarindex
        if multivar
            posind = zeros(Int,0);
            vals = zeros(0);
            for vi=1:length(var)
                if prob.ref_point[var[vi].index,1]
                    eii = prob.ref_point[var[vi].index, 2];
                    tmp = (grid_data.glbvertex[eii[1], eii[2]] - 1)*dofs_per_node + var_to_dofs[vi][1];
                    if length(prob.ref_point[var[vi].index, 3]) > 1
                        tmp = tmp:(tmp+length(prob.ref_point[var[vi].index, 3])-1);
                    end
                    posind = [posind; tmp];
                    vals = [vals; prob.ref_point[var[vi].index, 3]];
                end
            end
            if length(vals) > 0
                A = identity_rows(A, posind, length(b));
                b[posind] = vals;
            end
            
        else
            if prob.ref_point[var.index,1]
                eii = prob.ref_point[var.index, 2];
                posind = (grid_data.glbvertex[eii[1], eii[2]] - 1)*dofs_per_node + 1;
                if length(prob.ref_point[var.index, 3]) > 1
                    posind = posind:(posind+length(prob.ref_point[var[vi].index, 3])-1);
                else
                    posind = [posind];
                end
                A = identity_rows(A, posind, length(b));
                b[posind] = prob.ref_point[var.index, 3];
            end
        end
    end
    
    bc_time = Base.Libc.time() - bc_time;
    
    log_entry("Elemental loop time:     "*string(loop_time));
    # log_entry("Boundary condition time: "*string(bc_time));
    return (A, b);
end

# assembles the A and b in Au=b
function assemble_rhs_only(var, linear, face_linear, t=0.0, dt=0.0)
    Np = refel.Np;
    nel = mesh_data.nel;
    N1 = size(grid_data.allnodes,2);
    multivar = typeof(var) <: Array;
    maxvarindex = 0;
    if multivar
        # multiple variables being solved for simultaneously
        dofs_per_node = 0;
        var_to_dofs = [];
        for vi=1:length(var)
            tmp = dofs_per_node;
            dofs_per_node += length(var[vi].symvar.vals);
            push!(var_to_dofs, (tmp+1):dofs_per_node);
            maxvarindex = max(maxvarindex,var[vi].index);
        end
    else
        # one variable
        dofs_per_node = length(var.symvar.vals);
        maxvarindex = var.index;
    end
    Nn = dofs_per_node * N1;

    b = zeros(Nn);
    
    # Stiffness and mass are precomputed for uniform grid meshes
    if config.mesh_type == UNIFORM_GRID && config.geometry == SQUARE
        glb = grid_data.loc2glb[:,1];
        xe = grid_data.allnodes[:,glb[:]];
        (detJ, J) = geometric_factors(refel, xe);
        wgdetj = refel.wg .* detJ;
        if config.dimension == 1
            (RQ1, RD1) = build_deriv_matrix(refel, J);
            TRQ1 = RQ1';
            stiffness = [(TRQ1 * diagm(wgdetj) * RQ1)];
        elseif config.dimension == 2
            (RQ1, RQ2, RD1, RD2) = build_deriv_matrix(refel, J);
            (TRQ1, TRQ2) = (RQ1', RQ2');
            stiffness = [(TRQ1 * diagm(wgdetj) * RQ1) , (TRQ2 * diagm(wgdetj) * RQ2)];
        else
            (RQ1, RQ2, RQ3, RD1, RD2, RD3) = build_deriv_matrix(refel, J);
            (TRQ1, TRQ2, TRQ3) = (RQ1', RQ2', RQ3');
            stiffness = [(TRQ1 * diagm(wgdetj) * RQ1) , (TRQ2 * diagm(wgdetj) * RQ2) , (TRQ3 * diagm(wgdetj) * RQ3)];
        end
        mass = (refel.Q)' * diagm(wgdetj) * refel.Q;
    else
        stiffness = 0;
        mass = 0;
    end
    
    dim2face = [0,2,4,6];
    facerefel = build_refel(refel.dim-1, refel.N, dim2face[refel.dim], config.elemental_nodes);
    vol_J = Array{Jacobian,1}(undef,nel);
    
    # Elemental loop follows elemental ordering
    for e=elemental_order;
        glb = grid_data.loc2glb[:,e];       # global indices of this element's nodes for extracting values from var arrays
        xe = grid_data.allnodes[:,glb[:]];  # coordinates of this element's nodes for evaluating coefficient functions
        
        (detJ, J) = geometric_factors(refel, xe);
        vol_J[e] = J;
        
        rhsargs = (var, xe, glb, refel, RHS, t, dt, stiffness, mass);

        #linchunk = linear.func(args);  # get the elemental linear part
        if dofs_per_node == 1
            linchunk = linear.func(rhsargs);  # get the elemental linear part
            b[glb] .+= linchunk;

        elseif typeof(var) == Variable
            # only one variable, but more than one dof
            linchunk = linear.func(rhsargs);
            insert_linear!(b, linchunk, glb, 1:dofs_per_node, dofs_per_node);

        else
            linchunk = linear.func(rhsargs);
            insert_linear!(b, linchunk, glb, 1:dofs_per_node, dofs_per_node);

        end
    end
    
    # surface assembly for dg
    if !(face_linear===nothing)
        # dim2face = [0,2,4,6];
        # frefel = build_refel(refel.dim-1, refel.N, dim2face[refel.dim], config.elemental_nodes);
        
        for fid = 1:size(grid_data.face2glb,3)
            
            frefelind = [grid_data.faceRefelInd[1,fid], grid_data.faceRefelInd[2,fid]]; # refel based index of face in both elements
            
            face2glb = grid_data.face2glb[:,:,fid]; # local to global for face
            if frefelind[2] > 0 # not a boundary face
                flocal = [refel.face2local[frefelind[1]], refel.face2local[frefelind[2]]]; # local indices of face in both elements
            else # a boundary face
                face2glb[:,2] = face2glb[:,1]; # same global index for inside and out
                frefelind[2] = frefelind[1];
                flocal = [refel.face2local[frefelind[1]], refel.face2local[frefelind[1]]]; # local indices of face in both elements
            end
            
            facenodes = grid_data.allnodes[:,face2glb[:,1]]; # coordinates of this face's nodes for evaluating coefficient functions
            
            normal = grid_data.facenormals[:,fid]; # normal vector
            
            faceBID = mesh_data.bdryID[fid]; # BID of face (0 for interior)
            
            (fdetJ, fJ) = geometric_factors_face(refel, frefelind[1], facenodes); # compute geometric factors here for the face
            #fdetJ = [1];
            #fJ = [1];
            
            e1 = mesh_data.face2element[1,fid]; # element on side 1
            e2 = mesh_data.face2element[2,fid]; # and 2
            if e1==0 # boundary
                e1=e2;
            end
            if e2==0 # boundary
                e2=e1;
            end
            vol_J1 = vol_J[e1]; # volume gepmetric factors for e1
            vol_J2 = vol_J[e2]; # and e2
            
            loc2glb = [grid_data.loc2glb[:,e1], grid_data.loc2glb[:,e2]]; # volume local to global
            
            face_wgdetj = refel.surf_wg[1] .* fdetJ;
            
            rhsargs = (var, refel, loc2glb, fid, frefelind, facenodes, face2glb, normal, faceBID, fdetJ, fJ, vol_J1, vol_J2, face_wgdetj, RHS, t, dt);
            #lhsargs = (var, refel, loc2glb, fid, frefelind, facenodes, face2glb, normal, faceBID, fdetJ, fJ, vol_J1, vol_J2, face_wgdetj, LHS, t, dt);
            
            if dofs_per_node == 1
                linchunk = face_linear.func(rhsargs);  # get the elemental linear part
                #linchunk = the_desired(rhsargs);
                linchunk[1] = linchunk[1][flocal[1]];
                linchunk[2] = linchunk[2][flocal[2]];
                if faceBID == 0
                    b[face2glb[:,1]] .+= linchunk[1];
                    b[face2glb[:,2]] .+= linchunk[2];
                elseif mesh_data.face2element[1,fid] == 0
                    b[face2glb[:,2]] .+= linchunk[2];
                else
                    b[face2glb[:,1]] .+= linchunk[1];
                end
                
            end	 	
        end
    end
    
    # Boundary conditions
    bidcount = length(grid_data.bids); # the number of BIDs
    if dofs_per_node > 1
        if multivar
            dofind = 0;
            for vi=1:length(var)
                for compo=1:length(var[vi].symvar.vals)
                    dofind = dofind + 1;
                    for bid=1:bidcount
                        if prob.bc_type[var[vi].index, bid] == NO_BC
                            # do nothing
                        else
                            b = dirichlet_bc_rhs_only(b, prob.bc_func[var[vi].index, bid][compo], grid_data.bdry[bid], t, dofind, dofs_per_node);
                        end
                    end
                end
            end
        else
            for d=1:dofs_per_node
                #rows = ((d-1)*length(glb)+1):(d*length(glb));
                dofind = d;
                for bid=1:bidcount
                    if prob.bc_type[var.index, bid] == NO_BC
                        # do nothing
                    else
                        b = dirichlet_bc_rhs_only(b, prob.bc_func[var.index, bid][d], grid_data.bdry[bid], t, d, dofs_per_node);
                        if time_stepper.type == EULER_EXPLICIT || time_stepper.type == LSRK4 # explicit steppers
                            vecbdry = (grid_data.bdry[bid] .- 1) .* dofs_per_node .+ d;
                            b[vecbdry] = b[vecbdry] .- var.values[vecbdry];
                        end
                    end
                end
            end
        end
    else
        for bid=1:bidcount
            if prob.bc_type[var.index, bid] == NO_BC
                # do nothing
            else
                b = dirichlet_bc_rhs_only(b, prob.bc_func[var.index, bid][1], grid_data.bdry[bid], t);
                if time_stepper.type == EULER_EXPLICIT || time_stepper.type == LSRK4 # explicit steppers
                    b[grid_data.bdry[bid]] = b[grid_data.bdry[bid]] .- var.values[grid_data.bdry[bid]];
                end
            end
        end
    end
    
    # Reference points
    if size(prob.ref_point,1) >= maxvarindex
        if multivar
            posind = zeros(Int,0);
            vals = zeros(0);
            for vi=1:length(var)
                if prob.ref_point[var[vi].index,1]
                    eii = prob.ref_point[var[vi].index, 2];
                    tmp = (grid_data.glbvertex[eii[1], eii[2]] - 1)*dofs_per_node + var_to_dofs[vi][1];
                    if length(prob.ref_point[var[vi].index, 3]) > 1
                        tmp = tmp:(tmp+length(prob.ref_point[var[vi].index, 3])-1);
                    end
                    posind = [posind; tmp];
                    vals = [vals; prob.ref_point[var[vi].index, 3]];
                end
            end
            if length(vals) > 0
                b[posind] = vals;
            end
            
        else
            if prob.ref_point[var.index,1]
                eii = prob.ref_point[var.index, 2];
                posind = (grid_data.glbvertex[eii[1], eii[2]] - 1)*dofs_per_node + 1;
                if length(prob.ref_point[var.index, 3]) > 1
                    posind = posind:(posind+length(prob.ref_point[var[vi].index, 3])-1);
                end
                b[posind] = prob.ref_point[var.index, 3];
            end
        end
    end

    return b;
end

# Inset the single dof into the greater construct
function insert_linear!(b, bel, glb, dof, Ndofs)
    # group nodal dofs
    for d=1:length(dof)
        ind = glb.*Ndofs .- (Ndofs-dof[d]);
        ind2 = ((d-1)*length(glb)+1):(d*length(glb));

        b[ind] = b[ind] + bel[ind2];
    end
end

function insert_bilinear!(AI, AJ, AV, Astart, ael, glb, dof, Ndofs)
    Np = length(glb);
    # group nodal dofs
    for dj=1:length(dof)
        indj = glb.*Ndofs .- (Ndofs-dof[dj]);
        indj2 = ((dj-1)*Np+1):(dj*Np);
        for di=1:length(dof)
            indi = glb.*Ndofs .- (Ndofs-dof[di]);
            indi2 = ((di-1)*Np+1):(di*Np);
            
            #a[indi, indj] = a[indi, indj] + ael[indi2, indj2];
            
            for jj=1:Np
                offset = Astart + (jj-1 + Np*(dj-1))*Np*Ndofs + Np*(di-1) - 1;
                for ii=1:Np
                    AI[offset + ii] = indi[ii];
                    AJ[offset + ii] = indj[jj];
                    AV[offset + ii] = ael[indi2[ii], indj2[jj]];
                end
            end
        end
    end
    
end

function get_face_map(fn, en)
    fmap = zeros(Int, length(fn));
    for i=1:length(fn)
        for j=1:length(en)
            if en[j] == fn[i]
                fmap[i] = j;
                break;
            end
        end
    end
    return fmap;
end

function get_face_maps(fns, en)
    nfaces = size(fns,2);
    np = size(fns,1);
    fmap = zeros(Int, np, nfaces);
    for fi=1:nfaces
        for i=1:np
            for j=1:length(en)
                if en[j] == fns[i,fi]
                    fmap[i,fi] = j;
                    break;
                end
            end
        end
    end
    
    return fmap;
end

function face_boundary_condition(var, bid, inds, nodes, t)
    fnp = size(grid_data.face2glb,1);
    ave = zeros(fnp);
    if prob.bc_type[var.index, bid] == DIRICHLET
        val = prob.bc_func[var.index, bid][1];
        if typeof(val) <: Number
            for i=1:fnp
                ave[i]=val;
            end
            
        elseif typeof(val) == Coefficient && typeof(val.value[1]) == GenFunction
            if config.dimension == 1
                for i=1:fnp
                    ave[i]=val.value[1].func(nodes[1,i],0,0,t);
                end
            elseif config.dimension == 2
                for i=1:fnp
                    ave[i]=val.value[1].func(nodes[1,i],nodes[2,i],0,t);
                end
            else
                for i=1:fnp
                    ave[i]=val.value[1].func(nodes[1,i],nodes[2,i],nodes[3,i],t);
                end
            end
            
        elseif typeof(val) == GenFunction
            if config.dimension == 1
                for i=1:fnp
                    ave[i]=val.func(nodes[1,i],0,0,t);
                end
            elseif config.dimension == 2
                for i=1:fnp
                    ave[i]=val.func(nodes[1,i],nodes[2,i],0,t);
                end
            else
                for i=1:fnp
                    ave[i]=val.func(nodes[1,i],nodes[2,i],nodes[3,i],t);
                end
            end
        end
        
    elseif prob.bc_type[var.index, bid] == NO_BC
        for i=1:fnp
            ave[i]=var.values[1,inds[i]];
        end
    end
    
    return ave;
end

function place_sol_in_vars(var, sol, stepper)
    # place the values in the variable value arrays
    if typeof(var) <: Array
        tmp = 0;
        totalcomponents = 0;
        for vi=1:length(var)
            totalcomponents = totalcomponents + length(var[vi].symvar.vals);
        end
        for vi=1:length(var)
            components = length(var[vi].symvar.vals);
            for compi=1:components
                if stepper.type == EULER_EXPLICIT || stepper.type == LSRK4 # explicit steppers
                    var[vi].values[compi,:] += sol[(compi+tmp):totalcomponents:end];
                else # implicit steppers
                    var[vi].values[compi,:] = sol[(compi+tmp):totalcomponents:end];
                end
                tmp = tmp + 1;
            end
        end
    else
        components = length(var.symvar.vals);
        for compi=1:components
            if stepper.type == EULER_EXPLICIT || stepper.type == LSRK4 # explicit steppers
                var.values[compi,:] += sol[compi:components:end];
            else # implicit steppers
                var.values[compi,:] = sol[compi:components:end];
            end
        end
    end
end

end #module
