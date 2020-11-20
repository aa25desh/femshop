#=
This generates for the surface integrals
=#

function generate_code_layer_surface(ex, var, lorr)
    if use_cachesim
        if language == 0 || language == JULIA
            printerr("surface integrals not ready for cachesim")
            return nothing;
        elseif language == CPP
            printerr("surface integrals not ready for cachesim")
            return "";
        elseif language == MATLAB
            printerr("surface integrals not ready for cachesim")
            return "";
        end
    else
        if language == 0 || language == JULIA
            return generate_code_layer_julia_surface(ex, var, lorr);
        elseif language == CPP
            #return generate_code_layer_dendro_surface(ex, var, lorr);
            printerr("surface integrals only ready for Julia");
            return "";
        elseif language == MATLAB
            #return generate_code_layer_homg_surface(ex, var, lorr);
            printerr("surface integrals only ready for Julia");
            return "";
        end
    end
end

###############################################################################################################
# julia
###############################################################################################################

# Julia version returns an expression for the generated function for linear or bilinear term
function generate_code_layer_julia_surface(symex, var, lorr)
    # This is the basic info passed in "args"
    # args = (var, val_s1, node_s1, normal_s1, xe1, val_s2, node_s2, normal_s2, xe2, refel, face_refel, RHS/LHS, t, dt);
    code = Expr(:block);
    push!(code.args, :(var = args[1]));         # list of unknown variables for this expression
    push!(code.args, :(fmap_s1 = args[2]));     # extracts face nodes from the full element
    push!(code.args, :(node_s1 = args[3]));     # global indices of the nodes on side 1
    push!(code.args, :(enode_e1 = args[4]));    # global indices of the elemental nodes on side 1
    push!(code.args, :(normal_s1 = args[5]));   # normal vector on side 1
    push!(code.args, :(xf1 = args[6]));         # global coords of face nodes on side 1
    push!(code.args, :(xe1 = args[7]));         # global coords of element's nodes on side 1
    push!(code.args, :(fmap_s2 = args[8]));     # extracts face nodes from the full element
    push!(code.args, :(node_s2 = args[9]));     # global indices of the nodes on side 2
    push!(code.args, :(enode_e1 = args[10]));    # global indices of the elemental nodes on side 1
    push!(code.args, :(normal_s2 = args[11]));   # normal vector on side 2
    push!(code.args, :(xf2 = args[12]));        # global coords of face nodes on side 1
    push!(code.args, :(xe2 = args[13]));        # global coords of element's nodes on side 1
    push!(code.args, :(refel = args[14]));      # reference element for volume
    push!(code.args, :(face_refel = args[15])); # reference element for face
    push!(code.args, :(borl = args[16]));       # bilinear or linear? lhs or rhs?
    push!(code.args, :(time = args[17]));       # time for time dependent coefficients
    push!(code.args, :(dt = args[18]));         # dt for time dependent problems
    
    # Build geometric factors for both volume and surface
    push!(code.args, :((detJ, J) = geometric_factors(refel, xe1)));
    push!(code.args, :((face_detJ, face_J) = geometric_factors(face_refel, xf1)));
    #push!(code.args, :(wgdetj = refel.wg .* detJ));
    push!(code.args, :(face_wgdetj_s1 = zeros(length(refel.wg))));
    push!(code.args, :(face_wgdetj_s2 = zeros(length(refel.wg))));
    push!(code.args, :(face_wgdetj_s1[fmap_s1] = face_refel.wg .* face_detJ));
    push!(code.args, :(face_wgdetj_s2[fmap_s2] = face_refel.wg .* face_detJ));
    
    need_derivative = false;
    needed_coef = [];
    needed_coef_ind = [];
    needed_coef_deriv = [];
    test_ind = [];
    trial_ind = [];
    
    # For multi variables
    multivar = typeof(var) <:Array;
    varcount = 1;
    if multivar
        varcount = length(var);
        offset_ind = zeros(Int, varcount);
        tmp = length(var[1].symvar.vals);
        for i=2:length(var)
            offset_ind[i] = tmp;
            tmp = tmp + length(var[i].symvar.vals);
        end
    end
    
    # symex is an array of arrays of symengine terms, or array of arrays of arrays for multivar
    # turn each one into an Expr for translation purposes
    terms = [];
    if multivar
        for vi=1:varcount
            push!(terms, terms_to_expr(symex[vi]));
        end
    else
        terms = terms_to_expr(symex);
    end
    
    # two sets for two sides
    terms = [terms, terms];
    
    # Process the terms turning them into the code layer
    if multivar
        # for vi=1:varcount
        #     subtest_ind = [];
        #     subtrial_ind = [];
        #     for i=1:length(terms[vi])
        #         (codeterm, der, coe, coeind, coederiv, testi, trialj) = process_surface_term_julia(terms[vi][i], var, lorr, offset_ind);
        #         if coeind == -1
        #             # processing failed due to nonlinear term
        #             printerr("term processing failed for: "*string(terms[vi][i])*" , possible nonlinear term?");
        #             return nothing;
        #         end
        #         need_derivative = need_derivative || der;
        #         append!(needed_coef, coe);
        #         append!(needed_coef_ind, coeind);
        #         append!(needed_coef_deriv, coederiv);
        #         # change indices into one number
                
        #         push!(subtest_ind, testi);
        #         push!(subtrial_ind, trialj);
        #         terms[vi][i] = codeterm;
        #     end
        #     push!(test_ind, subtest_ind);
        #     push!(trial_ind, subtrial_ind);
        # end
    else
        for i=1:length(terms[1])
            (codeterms, der, coe, coeind, coederiv, testi, trialj) = process_surface_term_julia(terms[1][i], var, lorr);
            if coeind == -1
                # processing failed due to nonlinear term
                printerr("term processing failed for: "*string(terms[1][i])*" , possible nonlinear term?");
                return nothing;
            end
            need_derivative = need_derivative || der;
            append!(needed_coef, coe);
            append!(needed_coef_ind, coeind);
            append!(needed_coef_deriv, coederiv);
            # change indices into one number
            
            push!(test_ind, testi);
            push!(trial_ind, trialj);
            terms[1][i] = codeterms[1];
            terms[2][i] = codeterms[2];
        end
    end
    
    # If derivatives are needed, prepare the appropriate matrices
    if need_derivative
        if config.dimension == 1
            push!(code.args, :((RQ1,RD1) = build_deriv_matrix(refel, J)));
            push!(code.args, :(TRQ1 = RQ1'));
        elseif config.dimension == 2
            push!(code.args, :((RQ1,RQ2,RD1,RD2) = build_deriv_matrix(refel, J)));
            push!(code.args, :((TRQ1,TRQ2) = (RQ1',RQ2')));
        elseif config.dimension == 3
            push!(code.args, :((RQ1,RQ2,RQ3,RD1,RD2,RD3) = build_deriv_matrix(refel, J)));
            push!(code.args, :((TRQ1,TRQ2,TRQ3) = (RQ1',RQ2',RQ3')));
        end
    end
    
    # If coefficients need to be computed, do so
    # # First remove duplicates
    #println("coef-"*string(length(needed_coef))*": "*string(needed_coef));
    #println("ind-"*string(length(needed_coef_ind))*": "*string(needed_coef_ind));
    #println("der-"*string(length(needed_coef_deriv))*": "*string(needed_coef_deriv));
    unique_coef = [];
    unique_coef_ind = [];
    unique_coef_deriv = [];
    for i=1:length(needed_coef)
        already = false;
        for j=1:length(unique_coef)
            if unique_coef[j] === needed_coef[i] && unique_coef_ind[j] == needed_coef_ind[i] && unique_coef_deriv[j] == needed_coef_deriv[i]
                already = true;
            end
        end
        if !already
            #println("coef: "*string(needed_coef[i])*" , ind: "*string(needed_coef_ind[i])*" , deriv: "*string(needed_coef_deriv[i]));
            push!(unique_coef, needed_coef[i]);
            push!(unique_coef_ind, needed_coef_ind[i]);
            push!(unique_coef_deriv, needed_coef_deriv[i]);
        end
    end
    needed_coef = unique_coef;
    needed_coef_ind = unique_coef_ind;
    needed_coef_deriv = unique_coef_deriv;
    
    # For constant coefficients, this generates something like:
    ######################################
    # coef_n_i = a.value[i];
    ######################################
    
    # For variable coefficients, this generates something like:
    ######################################
    # coef_n_i = zeros(face_refel.Np);
    # for coefi = 1:face_refel.Np
    #     coef_n_i[coefi] = a.value[i].func(x[coefi,1], x[coefi,2],x[coefi,3],time);
    # end
    ######################################
    if length(needed_coef) > 0
        cloop = :(for coefi=1:refel.Np end);
        cloopin = Expr(:block);
        cargs = [:(xe1[coefi]); 0; 0; :time];
        if config.dimension == 2
            cargs = [:(xe1[coefi,1]); :(xe1[coefi,2]); 0; :time];
        elseif config.dimension == 3
            cargs = [:(xe1[coefi,1]); :(xe1[coefi,2]); :(xe1[coefi,3]); :time];
        end
        
        for i=1:length(needed_coef)
            if !(typeof(needed_coef[i]) <: Number || needed_coef[i] === :dt)
                cind = get_coef_index(needed_coef[i]);
                if cind >= 0
                    tag = string(cind);
                else
                    tag = string(needed_coef[i]);
                end
                #derivatives of coefficients
                tag = needed_coef_deriv[i][2] * tag;
                #tmps = "coef_"*tag*"_"*string(needed_coef_ind[i]);
                tmps1 = "coef_"*tag*"_"*string(needed_coef_ind[i])*"_s1";
                tmps2 = "coef_"*tag*"_"*string(needed_coef_ind[i])*"_s2";
                #tmpc = Symbol(tmps);
                tmpc1 = Symbol(tmps1);
                tmpc2 = Symbol(tmps2);
                
                (ctype, cval) = get_coef_val(needed_coef[i], needed_coef_ind[i]);
                if ctype == 1
                    # constant coefficient -> coef_n = cval
                    tmpn = cval;
                    push!(code.args, Expr(:(=), tmpc1, tmpn));
                    push!(code.args, Expr(:(=), tmpc2, tmpn));
                    #push!(code.args, Expr(:(=), tmpc, tmpn));
                elseif ctype == 2
                    # genfunction coefficients -> coef_n_i = coef.value[i].func(cargs)
                    tmpv = :(a[coefi]);
                    tmpv.args[1] = tmpc1;
                    tmpn = :(Femshop.genfunctions[$cval]); # Femshop.genfunctions[cval]
                    tmpb = :(a.func());
                    tmpb.args[1].args[1]= tmpn;
                    append!(tmpb.args, cargs);
                    push!(code.args, Expr(:(=), tmpc1, :(zeros(refel.Np)))); # allocate coef_n
                    push!(code.args, Expr(:(=), tmpc2, :(zeros(refel.Np))));
                    #push!(code.args, Expr(:(=), tmpc, tmpc1));
                    push!(cloopin.args, Expr(:(=), tmpv, tmpb)); # add it to the loop
                    
                elseif ctype == 3
                    # variable values -> coef_n = variable.values
                    if variables[cval].type == SCALAR
                        tmpb1 = :(copy(Femshop.variables[$cval].values[enode_e1])); 
                        tmpb2 = :(copy(Femshop.variables[$cval].values[enode_e2])); 
                    else
                        compo = needed_coef_ind[i];
                        tmpb1 = :(copy(Femshop.variables[$cval].values[$compo, enode_e1]));
                        tmpb2 = :(copy(Femshop.variables[$cval].values[$compo, enode_e2]));
                    end
                    
                    push!(code.args, Expr(:(=), tmpc1, tmpb1));
                    push!(code.args, Expr(:(=), tmpc2, tmpb2));
                    #push!(code.args, Expr(:(=), tmpc, tmpb1));
                end
                
            end# number?
        end# coef loop
        
        # Write the loop that computes coefficient values
        if length(cloopin.args) > 0
            cloop.args[2] = cloopin;
            push!(code.args, cloop); # add loop to code
        end
        
        # Apply derivatives and do ave and jump after the initializing loop
        # Derivs will look like: coef_i_j = RDn * coef_i_j
        # Ave will look like: coef_DGAVEu_j = (coef_u_j_s1 + coef_u_j_s2).*0.5
        for i=1:length(needed_coef_deriv)
            if length(needed_coef_deriv[i][2]) > 0
                cind = get_coef_index(needed_coef[i]);
                
                if cind >= 0
                    tag = string(cind);
                else
                    tag = string(needed_coef[i]);
                end
                #modifications of coefficients
                tag = needed_coef_deriv[i][2] * tag;
                #tmps = "coef_"*tag*"_"*string(needed_coef_ind[i]);
                tmps1 = "coef_"*tag*"_"*string(needed_coef_ind[i])*"_s1";
                tmps2 = "coef_"*tag*"_"*string(needed_coef_ind[i])*"_s2";
                #tmpc = Symbol(tmps);
                tmpc1 = Symbol(tmps1);
                tmpc2 = Symbol(tmps2);
                
                if length(needed_coef_deriv[i][3]) > 0 && !(typeof(needed_coef[i]) <: Number || needed_coef[i] === :dt)
                    
                    
                    dmat1 = Symbol("RD"*needed_coef_deriv[i][3]);
                    dmat2 = Symbol("RD"*needed_coef_deriv[i][3]);
                    tmpb1= :(length($tmpc1) == 1 ? 0 : $dmat1 * $tmpc1);
                    tmpb2= :(length($tmpc2) == 1 ? 0 : $dmat2 * $tmpc2);
                    
                    #push!(code.args, :(println( $tmpc )));
                    push!(code.args, Expr(:(=), tmpc1, tmpb1));
                    push!(code.args, Expr(:(=), tmpc2, tmpb2));
                    #push!(code.args, Expr(:(=), tmpc, tmpb1)); # ?? This is not useful. surface terms should not have this
                    #push!(code.args, :(println( $tmpc )));
                    #push!(code.args, :(println("-----------------------------------------------------------------------------")));
                    
                else  # Could be DGJUMP for jump, DGAVE for ave or versions with NORMDOTGRAD
                    if occursin("DGAVENORMDOTGRAD", needed_coef_deriv[i][2])
                        # {{n.grad(u)}}
                        if config.dimension == 1
                            #tmpb = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1]) .* 0.5);
                            # tmpb1 = :((RD1[fmap_s1,:]*$tmpc1 .* (normal_s1[1] * 0.5)));
                            # tmpb2 = :((RD1[fmap_s2,:]*$tmpc2 .* (normal_s1[1] * 0.5)));
                            tmpb1 = :((RD1*$tmpc1 .* (normal_s1[1] * 0.5)));
                            tmpb2 = :((RD1*$tmpc2 .* (normal_s1[1] * 0.5)));
                        elseif config.dimension == 2
                            # tmpb = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2] + 
                            #                 RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1] + RD2[fmap_s2,:]*$tmpc2 .* normal_s1[2]) .* 0.5);
                            # tmpb1 = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2]) .* 0.5);
                            # tmpb2 = :((RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1] + RD2[fmap_s2,:]*$tmpc2 .* normal_s1[2]) .* 0.5);
                            tmpb1 = :((RD1*$tmpc1 .* normal_s1[1] + RD2*$tmpc1 .* normal_s1[2]) .* 0.5);
                            tmpb2 = :((RD1*$tmpc2 .* normal_s1[1] + RD2*$tmpc2 .* normal_s1[2]) .* 0.5);
                        elseif config.dimension == 3
                            # tmpb = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2] + RD3[fmap_s1,:]*$tmpc1 .* normal_s1[3] +
                            #                 RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1] + RD2[fmap_s2,:]*$tmpc2 .* normal_s1[2] + RD3[fmap_s2,:]*$tmpc2 .* normal_s1[3]) .* 0.5);
                            # tmpb1 = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2] + RD3[fmap_s1,:]*$tmpc1 .* normal_s1[3]) .* 0.5);
                            # tmpb2 = :((RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1] + RD2[fmap_s2,:]*$tmpc2 .* normal_s1[2] + RD3[fmap_s2,:]*$tmpc2 .* normal_s1[3]) .* 0.5);
                            tmpb1 = :((RD1*$tmpc1 .* normal_s1[1] + RD2*$tmpc1 .* normal_s1[2] + RD3*$tmpc1 .* normal_s1[3]) .* 0.5);
                            tmpb2 = :((RD1*$tmpc2 .* normal_s1[1] + RD2*$tmpc2 .* normal_s1[2] + RD3*$tmpc2 .* normal_s1[3]) .* 0.5);
                        end
                    elseif occursin("DGAVE", needed_coef_deriv[i][2])
                        # {{u}} -> (fmap_s1(Q) + fmap_s2(Q))*0.5
                        #tmpb = :((refel.Q[fmap_s1,:]*$tmpc1 + refel.Q[fmap_s2,:]*$tmpc2) .* 0.5);
                        # tmpb1 = :((refel.Q[fmap_s1,:]*$tmpc1) .* 0.5);
                        # tmpb2 = :((refel.Q[fmap_s2,:]*$tmpc2) .* 0.5);
                        tmpb1 = :((refel.Q*$tmpc1) .* 0.5);
                        tmpb2 = :((refel.Q*$tmpc2) .* 0.5);
                    elseif occursin("DGJUMPNORMDOTGRAD", needed_coef_deriv[i][2])
                        # [[n.grad(u)]]
                        if config.dimension == 1
                            #tmpb = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] - RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1]));
                            # tmpb1 = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1]));
                            # tmpb2 = :((RD1[fmap_s2,:]*$tmpc2 .* -normal_s1[1]));
                            tmpb1 = :((RD1*$tmpc1 .* normal_s1[1]));
                            tmpb2 = :((RD1*$tmpc2 .* -normal_s1[1]));
                        elseif config.dimension == 2
                            # tmpb = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2] - 
                            #                 RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1] - RD2[fmap_s2,:]*$tmpc2 .* normal_s1[2]));
                            # tmpb1 = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2]));
                            # tmpb2 = :((RD1[fmap_s2,:]*$tmpc2 .* -normal_s1[1] + RD2[fmap_s2,:]*$tmpc2 .* -normal_s1[2]));
                            tmpb1 = :((RD1*$tmpc1 .* normal_s1[1] + RD2*$tmpc1 .* normal_s1[2]));
                            tmpb2 = :((RD1*$tmpc2 .* -normal_s1[1] + RD2*$tmpc2 .* -normal_s1[2]));
                        elseif config.dimension == 3
                            # tmpb = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2] + RD3[fmap_s1,:]*$tmpc1 .* normal_s1[3] -
                            #                 RD1[fmap_s2,:]*$tmpc2 .* normal_s1[1] - RD2[fmap_s2,:]*$tmpc2 .* normal_s1[2] - RD3[fmap_s2,:]*$tmpc2 .* normal_s1[3]));
                            # tmpb1 = :((RD1[fmap_s1,:]*$tmpc1 .* normal_s1[1] + RD2[fmap_s1,:]*$tmpc1 .* normal_s1[2] + RD3[fmap_s1,:]*$tmpc1 .* normal_s1[3]));
                            # tmpb2 = :((RD1[fmap_s2,:]*$tmpc2 .* -normal_s1[1] + RD2[fmap_s2,:]*$tmpc2 .* -normal_s1[2] + RD3[fmap_s2,:]*$tmpc2 .* -normal_s1[3]));
                            tmpb1 = :((RD1*$tmpc1 .* normal_s1[1] + RD2*$tmpc1 .* normal_s1[2] + RD3*$tmpc1 .* normal_s1[3]));
                            tmpb2 = :((RD1*$tmpc2 .* -normal_s1[1] + RD2*$tmpc2 .* -normal_s1[2] + RD3*$tmpc2 .* -normal_s1[3]));
                        end
                    elseif occursin("DGJUMP", needed_coef_deriv[i][2])
                        # [[u]] -> (fmap_s1(Q) - fmap_s2(Q))
                        #tmpb = :((refel.Q[fmap_s1,:]*$tmpc1 - refel.Q[fmap_s2,:]*$tmpc2));
                        # tmpb1 = :((refel.Q[fmap_s1,:]*$tmpc1));
                        # tmpb2 = :((-refel.Q[fmap_s2,:]*$tmpc2));
                        tmpb1 = :((refel.Q*$tmpc1));
                        tmpb2 = :((-refel.Q*$tmpc2));
                        
                    else
                        # tmpb1 = :(refel.Q[fmap_s1,:]*$tmpc1); # This should not happen?
                        # tmpb2 = :(refel.Q[fmap_s2,:]*$tmpc2);
                        tmpb1 = :(refel.Q*$tmpc1); # This should not happen?
                        tmpb2 = :(refel.Q*$tmpc2);
                    end
                    
                    #push!(code.args, Expr(:(=), tmpc, tmpb));
                    push!(code.args, Expr(:(=), tmpc1, tmpb1));
                    push!(code.args, Expr(:(=), tmpc2, tmpb2));
                    # push!(code.args, :(println("tmpc1="*string($tmpc1))));
                    # push!(code.args, :(println("tmpc2="*string($tmpc2))));
                end
                
            else
                # nothing?
            end
        end
        
    end# needed_coef loop
    
    # finally add the code expression
    # For multiple dofs per node it will be like:
    # [A11  A12  A13 ...] where the indices are from test_ind and trial_ind (vector components)
    # [A21  A22  A23 ...] Note: things will be rearranged when inserted into the global matrix/vector
    # [...              ]
    # [...              ]
    #
    # [b1 ] from test_ind
    # [b2 ]
    # [...]
    
    # Allocate if needed
    dofsper = 0;
    if typeof(var) <: Array
        for vi=1:length(var)
            dofsper = dofsper + length(var[vi].symvar.vals); # The number of components for this variable
        end
    else
        dofsper = length(var.symvar.vals);
    end
    
    if dofsper > 1
        if lorr == RHS
            push!(code.args, Expr(:(=), :element_vector_s1, :(zeros(refel.Np*$dofsper)))); # allocate vector
            push!(code.args, Expr(:(=), :element_vector_s2, :(zeros(refel.Np*$dofsper)))); # allocate vector
        else
            push!(code.args, Expr(:(=), :element_matrix_s1, :(zeros(refel.Np*$dofsper, refel.Np*$dofsper)))); # allocate matrix
            push!(code.args, Expr(:(=), :element_matrix_s2, :(zeros(refel.Np*$dofsper, refel.Np*$dofsper)))); # allocate matrix
        end
    end
    
    # If it was empty, just return zeros without doing any work
    if length(terms[1])==0 && length(terms[2])==0
        if lorr == LHS
            return :(return (zeros(args[14].Np*$dofsper, args[14].Np*$dofsper), zeros(args[14].Np*$dofsper, args[14].Np*$dofsper)));
        else
            return :(return (zeros(args[14].Np*$dofsper), zeros(args[14].Np*$dofsper)));
        end
    end
    
    result1 = nothing; # Will hold the returned expression
    result2 = nothing;
    if typeof(var) <: Array # multivar
        println("multivar not ready");
        # for vi=1:length(var)
        #     # Add terms into full matrix according to testind/trialind
        #     # Each component/dof should have one expression so that submatrix is only modified once.
        #     if lorr == LHS
        #         #comps = length(var.symvar.vals);
        #         comps = dofsper;
        #         submatrices = Array{Any,2}(undef, comps, comps);
        #         for smi=1:length(submatrices)
        #             submatrices[smi] = nothing;
        #         end
        #         for i=1:length(terms[vi])
        #             ti = test_ind[vi][i][1] + offset_ind[vi];
        #             tj = trial_ind[vi][i][1];
                    
        #             if submatrices[ti, tj] === nothing
        #                 submatrices[ti, tj] = terms[vi][i];
        #             else
        #                 addexpr = :(a+b);
        #                 addexpr.args[2] = submatrices[ti, tj];
        #                 addexpr.args[3] = terms[vi][i];
        #                 submatrices[ti, tj] = addexpr;
        #             end
        #         end
                
        #         for cj=1:comps
        #             for ci=1:comps
        #                 if !(submatrices[ci, cj] === nothing)
        #                     ti = ci-1;
        #                     tj = cj-1;
        #                     sti = :($ti*refel.Np + 1);
        #                     eni = :(($ti + 1)*refel.Np);
        #                     stj = :($tj*refel.Np + 1);
        #                     enj = :(($tj + 1)*refel.Np);
                            
        #                     push!(code.args, Expr(:(+=), :(element_matrix[$sti:$eni, $stj:$enj]), submatrices[ci, cj]));
        #                 end
        #             end
        #         end
                
        #         result = :element_matrix;
                
        #     else #RHS
        #         #comps = length(var.symvar.vals);
        #         comps = dofsper;
        #         submatrices = Array{Any,1}(undef, comps);
        #         for smi=1:length(submatrices)
        #             submatrices[smi] = nothing;
        #         end
        #         for i=1:length(terms[vi])
        #             ti = test_ind[vi][i][1] + offset_ind[vi];
                    
        #             if submatrices[ti] === nothing
        #                 submatrices[ti] = terms[vi][i];
        #             else
        #                 addexpr = :(a+b);
        #                 addexpr.args[2] = submatrices[ti];
        #                 addexpr.args[3] = terms[vi][i];
        #                 submatrices[ti] = addexpr;
        #             end
        #         end
                
        #         for ci=1:comps
        #             if !(submatrices[ci] === nothing)
        #                 ti = ci-1;
        #                 sti = :($ti*refel.Np + 1);
        #                 eni = :(($ti + 1)*refel.Np);
                        
        #                 push!(code.args, Expr(:(+=), :(element_vector[$sti:$eni]), submatrices[ci]));
        #             end
        #         end
                
        #         result = :element_vector;
                
        #     end
        # end
    else
        if length(terms[1]) > 1
            if var.type == SCALAR # Only one component
                tmp1 = :(a+b);
                tmp1.args = [:+];
                for i=1:length(terms[1])
                    push!(tmp1.args, terms[1][i]);
                end
                result1 = tmp1;
            else # More than one component
                # Add terms into full matrix according to testind/trialind
                # Each component/dof should have one expression so that submatrix is only modified once.
                if lorr == LHS
                    comps = length(var.symvar.vals);
                    submatrices = Array{Any,2}(undef, comps, comps);
                    for smi=1:length(submatrices)
                        submatrices[smi] = nothing;
                    end
                    for i=1:length(terms[1])
                        ti = test_ind[i][1];
                        tj = trial_ind[i][1];
                        
                        if submatrices[ti, tj] === nothing
                            submatrices[ti, tj] = terms[1][i];
                        else
                            addexpr = :(a+b);
                            addexpr.args[2] = submatrices[ti, tj];
                            addexpr.args[3] = terms[1][i];
                            submatrices[ti, tj] = addexpr;
                        end
                    end
                    
                    for cj=1:comps
                        for ci=1:comps
                            if !(submatrices[ci, cj] === nothing)
                                ti = ci-1;
                                tj = cj-1;
                                sti = :($ti*refel.Np + 1);
                                eni = :(($ti + 1)*refel.Np);
                                stj = :($tj*refel.Np + 1);
                                enj = :(($tj + 1)*refel.Np);
                                
                                push!(code.args, Expr(:(+=), :(element_matrix_s1[$sti:$eni, $stj:$enj]), submatrices[ci, cj]));
                            end
                        end
                    end
                    
                    result2 = :element_matrix_s1;
                    
                else #RHS
                    comps = length(var.symvar.vals);
                    submatrices = Array{Any,1}(undef, comps);
                    for smi=1:length(submatrices)
                        submatrices[smi] = nothing;
                    end
                    for i=1:length(terms[1])
                        ti = test_ind[i][1];
                        
                        if submatrices[ti] === nothing
                            submatrices[ti] = terms[1][i];
                        else
                            addexpr = :(a+b);
                            addexpr.args[2] = submatrices[ti];
                            addexpr.args[3] = terms[1][i];
                            submatrices[ti] = addexpr;
                        end
                    end
                    
                    for ci=1:comps
                        if !(submatrices[ci] === nothing)
                            ti = ci-1;
                            sti = :($ti*refel.Np + 1);
                            eni = :(($ti + 1)*refel.Np);
                            
                            push!(code.args, Expr(:(+=), :(element_vector_s1[$sti:$eni]), submatrices[ci]));
                        end
                    end
                    
                    result1 = :element_vector_s1;
                    
                end
            end
        elseif length(terms[1]) == 1# one term (one variable)
            result1 = terms[1][1];
        end
        # Do the same for side 2
        if length(terms[2]) > 1
            if var.type == SCALAR # Only one component
                tmp2 = :(a+b);
                tmp2.args = [:+];
                for i=1:length(terms[2])
                    push!(tmp2.args, terms[2][i]);
                end
                result2 = tmp1;
            else # More than one component
                # Add terms into full matrix according to testind/trialind
                # Each component/dof should have one expression so that submatrix is only modified once.
                if lorr == LHS
                    comps = length(var.symvar.vals);
                    submatrices = Array{Any,2}(undef, comps, comps);
                    for smi=1:length(submatrices)
                        submatrices[smi] = nothing;
                    end
                    for i=1:length(terms[2])
                        ti = test_ind[i][1];
                        tj = trial_ind[i][1];
                        
                        if submatrices[ti, tj] === nothing
                            submatrices[ti, tj] = terms[2][i];
                        else
                            addexpr = :(a+b);
                            addexpr.args[2] = submatrices[ti, tj];
                            addexpr.args[3] = terms[2][i];
                            submatrices[ti, tj] = addexpr;
                        end
                    end
                    
                    for cj=1:comps
                        for ci=1:comps
                            if !(submatrices[ci, cj] === nothing)
                                ti = ci-1;
                                tj = cj-1;
                                sti = :($ti*refel.Np + 1);
                                eni = :(($ti + 1)*refel.Np);
                                stj = :($tj*refel.Np + 1);
                                enj = :(($tj + 1)*refel.Np);
                                
                                push!(code.args, Expr(:(+=), :(element_matrix_s2[$sti:$eni, $stj:$enj]), submatrices[ci, cj]));
                            end
                        end
                    end
                    
                    result2 = :element_matrix_s2;
                    
                else #RHS
                    comps = length(var.symvar.vals);
                    submatrices = Array{Any,1}(undef, comps);
                    for smi=1:length(submatrices)
                        submatrices[smi] = nothing;
                    end
                    for i=1:length(terms[2])
                        ti = test_ind[i][1];
                        
                        if submatrices[ti] === nothing
                            submatrices[ti] = terms[2][i];
                        else
                            addexpr = :(a+b);
                            addexpr.args[2] = submatrices[ti];
                            addexpr.args[3] = terms[2][i];
                            submatrices[ti] = addexpr;
                        end
                    end
                    
                    for ci=1:comps
                        if !(submatrices[ci] === nothing)
                            ti = ci-1;
                            sti = :($ti*refel.Np + 1);
                            eni = :(($ti + 1)*refel.Np);
                            
                            push!(code.args, Expr(:(+=), :(element_vector_s2[$sti:$eni]), submatrices[ci]));
                        end
                    end
                    
                    result2 = :element_vector_s2;
                    
                end
            end
        elseif length(terms[2]) == 1# one term (one variable)
            result2 = terms[2][1];
        end
    end
    
    result = :((a,b));
    result.args[1] = result1;
    result.args[2] = result2;
    push!(code.args, Expr(:return, result));
    return code;
end

# Changes the symbolic layer term into a code layer term
# also records derivative and coefficient needs
function process_surface_term_julia(sterm, var, lorr, offset_ind=0)
    term1 = copy(sterm);
    term2 = copy(sterm);
    need_derivative = false;
    need_derivative_for_coefficient = false;
    needed_coef = [];
    needed_coef_ind = [];
    needed_coef_deriv = [];
    
    test_part1 = nothing;
    trial_part1 = nothing;
    coef_part1 = nothing;
    test_part2 = nothing;
    trial_part2 = nothing;
    coef_part2 = nothing;
    weight_part1 = :face_wgdetj_s1;
    weight_part2 = :face_wgdetj_s2;
    test_component = 0;
    trial_component = 0;
    
    # extract each of the factors.
    factors = separate_factors(term1);
    
    # strip off all negatives, combine and reattach at the end
    neg = false;
    for i=1:length(factors)
        if typeof(factors[i]) == Expr && factors[i].args[1] === :- && length(factors[i].args) == 2
            neg = !neg;
            factors[i] = factors[i].args[2];
        end
    end
    
    # Separate factors into test/trial/coefficient parts
    coef_facs = [];
    coef_inds = [];
    coef_derivs = [];
    coef_expr_facs = [];
    for i=1:length(factors)
        if typeof(factors[i]) <: Number
            push!(coef_facs, factors[i]);
            push!(coef_inds, -1);
            push!(coef_derivs, [nothing, "", ""]);
            
        elseif typeof(factors[i]) == Expr && factors[i].head === :call
            # These should both be purely coefficient/known expressions. 
            if factors[i].args[1] === :./
                # The second arg should be 1, the third should not contain an unknown or test symbol
                # The denominator expression needs to be processed completely
                (piece, nd, nc, nci, ncd) = process_known_expr_julia(factors[i].args[3]);
                need_derivative = need_derivative || nd;
                append!(needed_coef, nc);
                append!(needed_coef_ind, nci);
                append!(needed_coef_deriv, ncd);
                factors[i].args[3] = piece[1];
                push!(coef_expr_facs, factors[i]);
                #push!(coef_inds, 0);
                
            elseif factors[i].args[1] === :.^
                # The second arg is the thing raised
                (piece1, nd, nc, nci, ncd) = process_known_expr_julia(factors[i].args[2]);
                need_derivative = need_derivative || nd;
                append!(needed_coef, nc);
                append!(needed_coef_ind, nci);
                append!(needed_coef_deriv, ncd);
                factors[i].args[2] = piece1[1];
                # Do the same for the power just in case
                (piece2, nd, nc, nci, ncd) = process_known_expr_julia(factors[i].args[3]);
                need_derivative = need_derivative || nd;
                append!(needed_coef, nc);
                append!(needed_coef_ind, nci);
                append!(needed_coef_deriv, ncd);
                factors[i].args[3] = piece2[1];
                
                push!(coef_expr_facs, factors[i]);
                #push!(coef_inds, 0);
            elseif factors[i].args[1] === :sqrt
                factors[i].args[1] = :.^
                # The second arg is the thing sqrted
                (piece1, nd, nc, nci, ncd) = process_known_expr_julia(factors[i].args[2]);
                need_derivative = need_derivative || nd;
                append!(needed_coef, nc);
                append!(needed_coef_ind, nci);
                append!(needed_coef_deriv, ncd);
                factors[i].args[2] = piece1[1];
                # add a 1/2 power argument
                push!(factors[i].args, 1/2);
                
                push!(coef_expr_facs, factors[i]);
                #push!(coef_inds, 0);
            end
            
        else
            (index, v, mods) = extract_symbols(factors[i]);
            
            if is_test_func(v)
                test_component = index; # the vector index
                if length(mods) > 0
                    # Could be Dn for derivative, DGJUMP for jump, DGAVE for ave or versions with NORMDOTGRAD
                    if occursin("DGAVENORMDOTGRAD", mods[1])
                        # {{n.grad(u)}}
                        need_derivative = true;
                        if config.dimension == 1
                            #test_part = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ1[:,fmap_s2] .* normal_s1[1]) .* 0.5);
                            # test_part1 = :((TRQ1[:,fmap_s1] .* normal_s1[1]) .* 0.5);
                            # test_part2 = :((TRQ1[:,fmap_s2] .* normal_s1[1]) .* 0.5);
                            test_part1 = :((TRQ1 .* normal_s1[1]) .* 0.5);
                            test_part2 = :((TRQ1 .* normal_s1[1]) .* 0.5);
                        elseif config.dimension == 2
                            # test_part = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2] + 
                            #                 TRQ1[:,fmap_s2] .* normal_s1[1] + TRQ2[:,fmap_s2] .* normal_s1[2]) .* 0.5);
                            # test_part1 = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2]) .* 0.5);
                            # test_part2 = :((TRQ1[:,fmap_s2] .* normal_s1[1] + TRQ2[:,fmap_s2] .* normal_s1[2]) .* 0.5);
                            test_part1 = :((TRQ1 .* normal_s1[1] + TRQ2 .* normal_s1[2]) .* 0.5);
                            test_part2 = :((TRQ1 .* normal_s1[1] + TRQ2 .* normal_s1[2]) .* 0.5);
                        elseif config.dimension == 3
                            # test_part = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2] + TRQ3[:,fmap_s1] .* normal_s1[3] +
                            #                 TRQ1[:,fmap_s2] .* normal_s1[1] + TRQ2[:,fmap_s2] .* normal_s1[2] + TRQ3[:,fmap_s2] .* normal_s1[3]) .* 0.5);
                            # test_part1 = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2] + TRQ3[:,fmap_s1] .* normal_s1[3]) .* 0.5);
                            # test_part2 = :((TRQ1[:,fmap_s2] .* normal_s1[1] + TRQ2[:,fmap_s2] .* normal_s1[2] + TRQ3[:,fmap_s2] .* normal_s1[3]) .* 0.5);
                            test_part1 = :((TRQ1 .* normal_s1[1] + TRQ2 .* normal_s1[2] + TRQ3 .* normal_s1[3]) .* 0.5);
                            test_part2 = :((TRQ1 .* normal_s1[1] + TRQ2 .* normal_s1[2] + TRQ3 .* normal_s1[3]) .* 0.5);
                        end
                    elseif occursin("DGAVE", mods[1])
                        # {{u}} -> (fmap_s1(Q) + fmap_s2(Q))*0.5
                        #test_part = :((refel.Q[fmap_s1,:] + refel.Q[fmap_s2,:])' .* 0.5);
                        # test_part1 = :((refel.Q[fmap_s1,:])' .* 0.5);
                        # test_part2 = :((refel.Q[fmap_s2,:])' .* 0.5);
                        test_part1 = :((refel.Q)' .* 0.5);
                        test_part2 = :((refel.Q)' .* 0.5);
                    elseif occursin("DGJUMPNORMDOTGRAD", mods[1])
                        # [[n.grad(u)]]
                        need_derivative = true;
                        if config.dimension == 1
                            #test_part = :((TRQ1[:,fmap_s1] .* normal_s1[1] - TRQ1[:,fmap_s2] .* normal_s1[1]));
                            # test_part1 = :((TRQ1[:,fmap_s1] .* normal_s1[1]));
                            # test_part2 = :((TRQ1[:,fmap_s2] .* -normal_s1[1]));
                            test_part1 = :((TRQ1 .* normal_s1[1]));
                            test_part2 = :((TRQ1 .* -normal_s1[1]));
                        elseif config.dimension == 2
                            # test_part = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2] - 
                            #                 TRQ1[:,fmap_s2] .* normal_s1[1] - TRQ2[:,fmap_s2] .* normal_s1[2]));
                            # test_part1 = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2]));
                            # test_part2 = :((TRQ1[:,fmap_s2] .* -normal_s1[1] + TRQ2[:,fmap_s2] .* -normal_s1[2]));
                            test_part1 = :((TRQ1 .* normal_s1[1] + TRQ2 .* normal_s1[2]));
                            test_part2 = :((TRQ1 .* -normal_s1[1] + TRQ2 .* -normal_s1[2]));
                        elseif config.dimension == 3
                            # test_part = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2] + TRQ3[:,fmap_s1] .* normal_s1[3] -
                            #                 TRQ1[:,fmap_s2] .* normal_s1[1] - TRQ2[:,fmap_s2] .* normal_s1[2] - TRQ3[:,fmap_s2] .* normal_s1[3]));
                            # test_part1 = :((TRQ1[:,fmap_s1] .* normal_s1[1] + TRQ2[:,fmap_s1] .* normal_s1[2] + TRQ3[:,fmap_s1] .* normal_s1[3]));
                            # test_part2 = :((TRQ1[:,fmap_s2] .* -normal_s1[1] + TRQ2[:,fmap_s2] .* -normal_s1[2] + TRQ3[:,fmap_s2] .* -normal_s1[3]));
                            test_part1 = :((TRQ1 .* normal_s1[1] + TRQ2 .* normal_s1[2] + TRQ3 .* normal_s1[3]));
                            test_part2 = :((TRQ1 .* -normal_s1[1] + TRQ2 .* -normal_s1[2] + TRQ3 .* -normal_s1[3]));
                        end
                    elseif occursin("DGJUMP", mods[1])
                        # [[u]] -> (fmap_s1(Q) - fmap_s2(Q))
                        #test_part = :((refel.Q[fmap_s1,:] - refel.Q[fmap_s2,:])');
                        # test_part1 = :((refel.Q[fmap_s1,:])');
                        # test_part2 = :((-refel.Q[fmap_s2,:])');
                        test_part1 = :((refel.Q)');
                        test_part2 = :((-refel.Q)');
                    elseif occursin("D", mods[1])
                        # TODO more than one derivative mod
                        need_derivative = true;
                        dmat = Symbol("TRQ"*mods[1][2]);
                        test_part1 = dmat;
                        test_part2 = dmat;
                    end
                else
                    # no mods
                    test_part1 = :(refel.Q');
                    test_part2 = :(refel.Q');
                end
            elseif is_unknown_var(v, var) && lorr == LHS # If rhs, treat as a coefficient
                if !(trial_part1 === nothing)
                    # Two unknowns multiplied in this term. Nonlinear. abort.
                    printerr("Nonlinear term. Code layer incomplete.");
                    return (-1, -1, -1, -1, -1, -1);
                end
                trial_component = index;
                #offset component for multivar
                trial_var = var;
                if typeof(var) <:Array
                    for vi=1:length(var)
                        if v === var[vi].symbol
                            trial_component = trial_component .+ offset_ind[vi];
                            trial_var = var[vi];
                        end
                    end
                end
                if length(mods) > 0
                    # Could be Dn for derivative, DGJUMP for jump, DGAVE for ave or versions with NORMDOTGRAD
                    if occursin("DGAVENORMDOTGRAD", mods[1])
                        # {{n.grad(u)}}
                        need_derivative = true;
                        if config.dimension == 1
                            #trial_part = :((RQ1[fmap_s1,:] .* normal_s1[1] + RQ1[fmap_s2,:] .* normal_s1[1]) .* 0.5);
                            trial_part1 = :((RQ1 .* normal_s1[1]) .* 0.5);
                            trial_part2 = :((RQ1 .* normal_s1[1]) .* 0.5);
                        elseif config.dimension == 2
                            # trial_part = :((RQ1[fmap_s1,:] .* normal_s1[1] + RQ2[fmap_s1,:] .* normal_s1[2] + 
                            #                 RQ1[fmap_s2,:] .* normal_s1[1] + RQ2[fmap_s2,:] .* normal_s1[2]) .* 0.5);
                            trial_part1 = :((RQ1 .* normal_s1[1] + RQ2 .* normal_s1[2]) .* 0.5);
                            trial_part2 = :((RQ1 .* normal_s1[1] + RQ2 .* normal_s1[2]) .* 0.5);
                        elseif config.dimension == 3
                            # trial_part = :((RQ1[fmap_s1,:] .* normal_s1[1] + RQ2[fmap_s1,:] .* normal_s1[2] + RQ3[fmap_s1,:] .* normal_s1[3] +
                            #                 RQ1[fmap_s2,:] .* normal_s1[1] + RQ2[fmap_s2,:] .* normal_s1[2] + RQ3[fmap_s2,:] .* normal_s1[3]) .* 0.5);
                            trial_part1 = :((RQ1 .* normal_s1[1] + RQ2 .* normal_s1[2] + RQ3 .* normal_s1[3]) .* 0.5);
                            trial_part2 = :((RQ1 .* normal_s1[1] + RQ2 .* normal_s1[2] + RQ3 .* normal_s1[3]) .* 0.5);
                        end
                    elseif occursin("DGAVE", mods[1])
                        # {{u}} -> (fmap_s1(Q) + fmap_s2(Q))*0.5
                        #trial_part = :((refel.Q[fmap_s1,:] + refel.Q[fmap_s2,:])' .* 0.5);
                        trial_part1 = :((refel.Q) .* 0.5);
                        trial_part2 = :((refel.Q) .* 0.5);
                    elseif occursin("DGJUMPNORMDOTGRAD", mods[1])
                        # [[n.grad(u)]]
                        need_derivative = true;
                        if config.dimension == 1
                            #trial_part = :((RQ1[fmap_s1,:] .* normal_s1[1] - RQ1[fmap_s2,:] .* normal_s1[1]));
                            trial_part1 = :((RQ1 .* normal_s1[1]));
                            trial_part2 = :((RQ1 .* -normal_s1[1]));
                        elseif config.dimension == 2
                            # trial_part = :((RQ1[fmap_s1,:] .* normal_s1[1] + RQ2[fmap_s1,:] .* normal_s1[2] - 
                            #                 RQ1[fmap_s2,:] .* normal_s1[1] - RQ2[fmap_s2,:] .* normal_s1[2]));
                            trial_part1 = :((RQ1 .* normal_s1[1] + RQ2 .* normal_s1[2]));
                            trial_part2 = :((RQ1 .* -normal_s1[1] + RQ2 .* -normal_s1[2]));
                        elseif config.dimension == 3
                            # trial_part = :((RQ1[fmap_s1,:] .* normal_s1[1] + RQ2[fmap_s1,:] .* normal_s1[2] + RQ3[fmap_s1,:] .* normal_s1[3] -
                            #                 RQ1[fmap_s2,:] .* normal_s1[1] - RQ2[fmap_s2,:] .* normal_s1[2] - RQ3[fmap_s2,:] .* normal_s1[3]));
                            trial_part1 = :((RQ1 .* normal_s1[1] + RQ2 .* normal_s1[2] + RQ3 .* normal_s1[3]));
                            trial_part2 = :((RQ1 .* -normal_s1[1] + RQ2 .* -normal_s1[2] + RQ3 .* -normal_s1[3]));
                        end
                    elseif occursin("DGJUMP", mods[1])
                        # [[u]] -> (fmap_s1(Q) - fmap_s2(Q))
                        #trial_part = :((refel.Q[fmap_s1,:] - refel.Q[fmap_s2,:])');
                        trial_part1 = :((refel.Q));
                        trial_part2 = :((-refel.Q));
                    elseif occursin("D", mods[1])
                        # TODO more than one derivative mod
                        need_derivative = true;
                        dmat = Symbol("RQ"*mods[1][2]);
                        trial_part1 = dmat;
                        trial_part2 = dmat;
                    end
                else
                    # no mods
                    trial_part1 = :(refel.Q);
                    trial_part2 = :(refel.Q);
                end
                
            else # coefficients
                if length(index) == 1
                    ind = index[1];
                end
                # Check for derivative mods
                if typeof(v) == Symbol && !(v ===:dt)
                    if length(mods) > 0
                        # Could be Dn for derivative, DGJUMP for jump, DGAVE for ave or versions with NORMDOTGRAD
                        if occursin("DGAVENORMDOTGRAD", mods[1])
                            # {{n.grad(u)}}
                            push!(needed_coef_deriv, [v, mods[1], ""]);
                        elseif occursin("DGAVE", mods[1])
                            # {{u}}
                            push!(needed_coef_deriv, [v, mods[1], ""]);
                        elseif occursin("DGJUMPNORMDOTGRAD", mods[1])
                            # [[n.grad(u)]]
                            push!(needed_coef_deriv, [v, mods[1], ""]);
                        elseif occursin("DGJUMP", mods[1])
                            # [[u]]
                            push!(needed_coef_deriv, [v, mods[1], ""]);
                        elseif occursin("D", mods[1])
                            need_derivative = true;
                            need_derivative_for_coefficient = false;
                            
                            push!(needed_coef_deriv, [v, mods[1], mods[1][2]]);
                        end
                        
                    else
                        push!(needed_coef_deriv, [v, "", ""]);
                    end
                    push!(needed_coef, v);
                    push!(needed_coef_ind, ind);
                    
                    push!(coef_derivs, needed_coef_deriv[end]);
                    
                else
                    push!(coef_derivs, [nothing, "", ""]);
                end
                
                push!(coef_facs, v);
                push!(coef_inds, ind);
            end
        end
        
    end # factors loop
    
    # If there's no trial part, need to do this
    # if trial_part === nothing
    #     trial_part = :(refel.Q[fmap_s1,:]);
    # end
    
    # build coefficient parts
    if length(coef_facs) > 0
        for j=1:length(coef_facs)
            tmp = coef_facs[j];
            #println("coef_facs: "*string(tmp)*" : "*string(typeof(tmp)));
            if typeof(tmp) == Symbol && !(tmp ===:dt)
                ind = get_coef_index(coef_facs[j]);
                if ind >= 0
                    tag = string(ind);
                else
                    tag = string(tmp);
                end
                #derivatives of coefficients
                tag = coef_derivs[j][2] * tag;
                tmps1 = "coef_"*tag*"_"*string(coef_inds[j])*"_s1";
                tmp1 = Symbol(tmps1);
                tmps2 = "coef_"*tag*"_"*string(coef_inds[j])*"_s2";
                tmp2 = Symbol(tmps2);
                
            end
            if j>1
                coef_part1 = :($coef_par1 .* $tm1);
                coef_part2 = :($coef_par2 .* $tm2);
            else
                coef_part1 = tmp1;
                coef_part2 = tmp2;
            end
        end
    end
    
    if length(coef_expr_facs) > 0
        for j=1:length(coef_expr_facs)
            tmp = coef_expr_facs[j];
            if !(coef_part1 === nothing)
                coef_part1 = :($coef_part1 .* $tmp);
            else
                coef_part1 = tmp;
            end
            if !(coef_part2 === nothing)
                coef_part2 = :($coef_part2 .* $tmp);
            else
                coef_part2 = tmp;
            end
        end
    end
    
    # If there's no test part this is probably a denominator expression being processed and should only contain coefficients/knowns
    if test_part1 === nothing
        #
        #
    else
        term1 = test_part1;
        if !(coef_part1 === nothing)
            if lorr == LHS
                term1 = :($test_part1 * (diagm($weight_part1 .* $coef_part1) * $trial_part1));
            else # RHS
                if trial_part1 === nothing
                    term1 = :($test_part1 * ($weight_part1 .* ($coef_part1)));
                else
                    # This should never happen
                    # term = :($test_part * ($weight_part1 .* ($trial_part * $coef_part)));
                    println("There should be no trial part in rhs.")
                end
            end
            
        else
            term1 = :($test_part1 * diagm($weight_part1) * $trial_part1);
        end
        
        if neg
            negex = :(-a);
            negex.args[2] = copy(term1);
            term1 = negex;
        end
    end
    if test_part2 === nothing
        #
        #
    else
        term2 = test_part2
        if !(coef_part2 === nothing)
            if lorr == LHS
                term2 = :($test_part2 * (diagm($weight_part2 .* $coef_part2) * $trial_part2));
            else # RHS
                if trial_part2 === nothing
                    term2 = :($test_part2 * ($weight_part2 .* ($coef_part2)));
                else
                    # This should never happen
                    # term = :($test_part * ($weight_part2 .* ($trial_part * $coef_part)));
                    println("There should be no trial part in rhs.")
                end
            end
            
        else
            term2 = :($test_part2 * diagm($weight_part2) * $trial_part2);
        end
        
        if neg
            negex = :(-a);
            negex.args[2] = copy(term2);
            term2 = negex;
        end
    end
    
    return ((term1, term2), need_derivative, needed_coef, needed_coef_ind, needed_coef_deriv, test_component, trial_component);
end
