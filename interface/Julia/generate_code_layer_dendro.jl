
###############################################################################################################
# dendro
###############################################################################################################

# Dendro version returns a string that will be included in either the feMatrix or feVector
function generate_code_layer_dendro(symex, var, lorr)
    code = ""; # the code will be in this string
    
    need_derivative = false;
    term_derivative = [];
    needed_coef = [];
    needed_coef_ind = [];
    test_ind = [];
    trial_ind = [];
    
    to_delete = []; # arrays allocated with new that need deletion
    
    # symex is an array of arrays of symengine terms
    # turn each one into an Expr
    terms = [];
    sz = size(symex);
    if length(sz) == 1 # scalar or vector
        for i=1:length(symex)
            for ti=1:length(symex[i])
                push!(terms, Meta.parse(string(symex[i][ti])));
            end
        end
    elseif length(sz) == 2 # matrix
        #TODO
    end
    
    
    
    # Process the terms turning them into the code layer
    # cindex = 0;
    # for i=1:length(terms)
    #     (codeterm, der, coe) = process_term_dendro(terms[i], cindex, length(terms), i, var, lorr);
    #     need_derivative = need_derivative || der;
    #     push!(term_derivative, der);
    #     append!(needed_coef, coe);
    #     cindex = length(needed_coef);
    #     push!(code_terms, codeterm);
    # end
    # Process the terms turning them into the code layer
    code_terms = [];
    for i=1:length(terms)
        (codeterm, der, coe, coeind, testi, trialj) = process_term_dendro(terms[i], length(terms), i, var, lorr);
        if coeind == -1
            # processing failed due to nonlinear term
            printerr("term processing failed for: "*string(terms[i]));
            return nothing;
        end
        need_derivative = need_derivative || der;
        append!(needed_coef, coe);
        append!(needed_coef_ind, coeind);
        # change indices into one number
        
        push!(test_ind, testi);
        push!(trial_ind, trialj);
        push!(code_terms, codeterm);
    end
    
    # If coefficients need to be computed, do so
    # # First remove duplicates
    unique_coef = [];
    unique_coef_ind = [];
    for i=1:length(needed_coef)
        already = false;
        for j=1:length(unique_coef)
            if unique_coef[j] === needed_coef[i] && unique_coef_ind[j] == needed_coef_ind[i]
                already = true;
            end
        end
        if !already
            push!(unique_coef, needed_coef[i]);
            push!(unique_coef_ind, needed_coef_ind[i]);
        end
    end
    needed_coef = unique_coef;
    needed_coef_ind = unique_coef_ind;
    
    # For constant coefficients, this generates something like:
    ######################################
    # double coef_n_i = a_i;
    ######################################
    
    # For variable coefficients, this generates something like:
    ######################################
    # double* coef_n_i = new double[nPe];
    # double val;
    # for(unsigned int i=0; i<nPe; i++){
    #     a_i(coords[i*3+0], coords[i*3+0], coords[i*3+0], &val);
    #     coef_n_i[coefi] = val;
    # }
    ######################################
    coef_alloc = "";
    coef_loop = "";
    if length(needed_coef) > 0
        for i=1:length(needed_coef)
            if !(typeof(needed_coef[i]) <: Number || needed_coef[i] === :dt)
                cind = get_coef_index(needed_coef[i]);
                if cind < 0
                    # probably a variable
                    cind = string(needed_coef[i]);
                    # This presents a problem in dendro. TODO
                    printerr("Dendro not yet available for multivariate problems. Expect an error.");
                end
                # The string name for this coefficient
                cname = "coef_"*string(cind)*"_"*string(needed_coef_ind[i]);
                
                (ctype, cval) = get_coef_val(needed_coef[i], needed_coef_ind[i]);
                
                if ctype == 1
                    # constant coefficient -> coef_n_i = cval
                    coef_alloc *= "double "*cname*" = "*string(cval)*";\n";
                    
                elseif ctype == 2
                    # genfunction coefficients -> coef_n_i = coef.value[i].func(cargs)
                    coef_alloc *= "double* "*cname*" = new double[nPe];\n";
                    push!(to_delete, cname);
                    coef_loop *= "    "*cval*"(coords[i*3+0], coords[i*3+1], coords[i*3+2], &cval);\n";
                    coef_loop *= "    "*cname*"[i] = cval;\n";
                elseif ctype == 3
                    # variable values -> coef_n = variable.values
                    #TODO THIS IS AN ERROR. multivariate support needed.
                    coef_alloc *= "double "*cname*" = 0;\n";
                end
                
            end
        end
        # add the coef loop if needed
        if length(coef_loop) > 1
            coef_loop = "double cval;\nfor(unsigned int i=0; i<nPe; i++){\n"*coef_loop*"}\n";
        end
    end
    
    # If temp storage was needed for multiple terms, allocate
    temp_alloc = "";
    if length(terms) > 1
        for i=1:length(terms)
            temp_alloc *= "double* out_"*string(i)*" = new double[nPe];\n";
            push!(to_delete, "out_"*string(i));
        end
    end
    
    # delete any allocated arrays
    dealloc = "";
    for i=1:length(to_delete)
        dealloc *= "delete [] "*to_delete[i]*";\n";
    end
    
    dofsper = 1;
    if typeof(var) <: Array
        for vi=1:length(var)
            dofsper += length(var[vi].symvar.vals); # The number of components for this variable
        end
    elseif !(var.type == SCALAR)
        dofsper = length(var.symvar.vals);
    end
    # Not ready
    if dofsper > 1
        printerr("dendro not ready for multi dofs per node. Expect errors");
    end
    
    # Put the pieces together
    code = temp_alloc * coef_alloc * coef_loop;
    for i=1:length(terms)
        code *= code_terms[i] * "\n";
    end
    if length(terms) > 1 # combine the terms' temp arrays
        combine_loop = "out_1[i]";
        for i=2:length(terms)
            combine_loop *= "+out_"*string(i)*"[i]";
        end
        code *= 
"\nfor(unsigned int i=0;i<nPe;i++){
    out[i]="*combine_loop*";
}\n";
    end
    code *= dealloc;
    
    return code;
end

# Changes the symbolic layer term into a code layer term
# also records derivative and coefficient needs
function process_term_dendro(sterm, termcount, thisterm, var, lorr)
    term = copy(sterm);
    need_derivative = false;
    needed_coef = [];
    needed_coef_ind = [];
    
    test_part = "";
    trial_part = "";
    coef_part = "";
    test_component = 0;
    trial_component = 0;
    deriv_dir = 0;
    
    # Will the output of this term be stored in "out" or a temp value "out_n"
    out_name = "out";
    if termcount > 1
        out_name = "out_"*string(thisterm);
    end
    
    # extract each of the factors.
    factors = separate_factors(term);
    
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
    for i=1:length(factors)
        (index, v, mods) = extract_symbols(factors[i]);
        
        if is_test_func(v)
            test_component = index; # the vector index
            if length(mods) > 0
                # TODO more than one derivative mod
                need_derivative = true;
                deriv_dir = parse(Int, mods[1][2]);
                if deriv_dir == 1
                    test_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,DgT,"*out_name*",imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,QT1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,QT1d,imV2,"*out_name*");\n";
                elseif deriv_dir == 2
                    test_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,QT1d,"*out_name*",imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,DgT,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,QT1d,imV2,"*out_name*");\n";
                elseif deriv_dir == 3
                    test_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,QT1d,"*out_name*",imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,QT1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,DgT,imV2,"*out_name*");\n";
                elseif deriv_dir == 4
                    # This will eventually be a time derivative
                    printerr("Derivative index problem in "*string(factors[i]));
                else
                    printerr("Derivative index problem in "*string(factors[i]));
                end
            else
                # no derivative mods
                test_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,QT1d,out,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,QT1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,QT1d,imV2,"*out_name*");\n";
            end
        elseif is_unknown_var(v, var)
            if !(trial_part == "")
                # Two unknowns multiplied in this term. Nonlinear. abort.
                printerr("Nonlinear term. Code layer incomplete.");
                return (-1, -1, -1, -1, -1, -1);
            end
            trial_component = index;
            if length(mods) > 0
                # TODO more than one derivative mod
                need_derivative = true;
                deriv_dir = parse(Int, mods[1][2]);
                if deriv_dir == 1
                    trial_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,Dg,in,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,Q1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,Q1d,imV2,"*out_name*");\n";
                elseif deriv_dir == 2
                    trial_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,Q1d,in,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,Dg,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,Q1d,imV2,"*out_name*");\n";
                elseif deriv_dir == 3
                    trial_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,Q1d,in,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,Q1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,Dg,imV2,"*out_name*");\n";
                elseif deriv_dir == 4
                    # This will eventually be a time derivative
                    printerr("Derivative index problem in "*string(factors[i]));
                else
                    printerr("Derivative index problem in "*string(factors[i]));
                end
            else
                # no derivative mods
                trial_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,Q1d,in,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,Q1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,Q1d,imV2,"*out_name*");\n";
            end
        else
            if length(index) == 1
                ind = index[1];
            end
            push!(coef_facs, v);
            push!(coef_inds, ind);
        end
    end
    
    # If rhs, change var into var.values and treat as a coefficient
    if lorr == RHS && !(trial_part === nothing)
        # tmpv = :(a.values[gbl]);
        # tmpv.args[1].args[1] = var.symbol; #TODO, will not work for var=array
        # push!(coef_facs, tmpv);
        # push!(coef_inds, trial_component);
    end
    
    # If there was no trial part, it's an RHS and we need to finish the quadrature with this
    if trial_part == ""
        trial_part = 
"DENDRO_TENSOR_IIAX_APPLY_ELEM(nrp,Q1d,in,imV1);
DENDRO_TENSOR_IAIX_APPLY_ELEM(nrp,Q1d,imV1,imV2);
DENDRO_TENSOR_AIIX_APPLY_ELEM(nrp,Q1d,imV2,"*out_name*");\n";
    end
    
    # build weight/coefficient parts
    idxstr = "[i]";
    weight_part = "W1d[i]";
    if config.dimension == 2
        idxstr = "[j*nrp+i]";
        weight_part = "W1d[i]*W1d[j]";
    elseif config.dimension == 3
        idxstr = "[(k*nrp+j)*nrp+i]";
        weight_part = "W1d[i]*W1d[j]*W1d[k]";
    end
    
    # If term is negative, apply it here
    if neg
        weight_part = "-"*weight_part;
    end
    
    # Multiply by coefficients inside integral if needed
    if length(coef_facs) > 0 && lorr == LHS
        for j=1:length(coef_facs)
            tmp = coef_facs[j];
            if typeof(tmp) == Symbol && !(tmp ===:dt)
                push!(needed_coef, tmp);
                push!(needed_coef_ind, coef_inds[j]);
                ind = get_coef_index(coef_facs[j]);
                if ind >= 0
                    tmp = "coef_"*string(ind)*"_"*string(coef_inds[j])*idxstr;
                else
                    tmp = "coef_"*string(tmp)*"_"*string(coef_inds[j])*idxstr;
                end
            else
                tmp = string(tmp);
            end
            if j>1
                coef_part = coef_part*"*"*tmp;
            else
                coef_part = tmp;
            end
        end
        weight_part = weight_part*" * "*coef_part;
    end
    
    # build the inner weight/coef loop
    body = out_name*"[k*(eleOrder+1)*(eleOrder+1)+j*(eleOrder+1)+i]*=(Jx*Jy*Jz*"*weight_part*");";
    if need_derivative
        if deriv_dir == 1
            body = out_name*"[k*(eleOrder+1)*(eleOrder+1)+j*(eleOrder+1)+i]*=( ((Jy*Jz)/Jx)*"*weight_part*");";
        elseif deriv_dir == 2
            body = out_name*"[k*(eleOrder+1)*(eleOrder+1)+j*(eleOrder+1)+i]*=( ((Jx*Jz)/Jy)*"*weight_part*");";
        elseif deriv_dir == 3
            body = out_name*"[k*(eleOrder+1)*(eleOrder+1)+j*(eleOrder+1)+i]*=( ((Jx*Jy)/Jz)*"*weight_part*");";
        else
            # there will be an error
        end
    end
    
    wcloop =
"for(unsigned int k=0;k<(eleOrder+1);k++){
    for(unsigned int j=0;j<(eleOrder+1);j++){
        for(unsigned int i=0;i<(eleOrder+1);i++){
            "*body*"
        }
    }
}\n";
    
    # Put the pieces together
    term = trial_part * "\n" * wcloop * "\n" * test_part;
#     if need_derivative
#         term *= 
# "\n"*"for(unsigned int i=0;i<nPe;i++){
#     "*out_name*"[i]=Qx[i]+Qy[i]+Qz[i];
# }\n";
#     end
    
    return (term, need_derivative, needed_coef, needed_coef_ind, test_component, trial_component);
end
