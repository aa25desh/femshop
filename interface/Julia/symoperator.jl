#=
Operators that work on SymType objects
=#

# An abstract operator type.
struct SymOperator
    symbol::Symbol      # The name used in the input expression
    op                  # Function handle for the operator
end

# Initialize predefined operators
# op_names = [:dot, :inner, :cross, :grad, :div, :curl, :laplacian];
function init_ops()
    ops = [];
    push!(ops, SymOperator(:dot, sym_dot_op));
    push!(ops, SymOperator(:inner, sym_inner_op));
    push!(ops, SymOperator(:cross, sym_cross_op));
    push!(ops, SymOperator(:grad, sym_grad_op));
    push!(ops, SymOperator(:div, sym_div_op));
    push!(ops, SymOperator(:curl, sym_curl_op));
    push!(ops, SymOperator(:laplacian, sym_laplacian_op));
    return ops;
end

#########################################################################
# algebraic ops
#########################################################################

function sym_dot_op(a,b)
    if (size(a) == size(b)) && (ndims(a) == 1)
        return [transpose(a)*b];
    else
        printerr("Usupported dimensions for: dot(a,b), sizes: a="*string(size(a))*", b="*string(size(b))*")");
    end
end

function sym_inner_op(a,b)
    if size(a) == size(b)
        c = 0;
        for i=1:length(a)
            c += a[i]*b[i];
        end
        return [c];
    else
        printerr("Unequal dimensions for: inner(a,b), sizes: a="*string(size(a))*", b="*string(size(b))*")");
    end
end

function sym_cross_op(a,b)
    if size(a) == size(b)
        if size(a) == (1,) # scalar
            # return [a[1]*b[1]]; # Should we allow this?
        elseif ndims(a) == 1 # vector
            if length(a) == 2 # 2D
                # return [a[1]*b[2] - a[2]*b[1]]; # Should we allow this?
            elseif length(a) == 3 # 3D
                return [a[2]*b[3]-a[3]*b[2], a[3]*b[1]-a[1]*b[3], a[1]*b[2]-a[2]*b[1]];
            end
        else
            printerr("Unsupported dimensions for: cross(a,b), sizes: a="*string(size(a))*", b="*string(size(b))*")");
        end
    else
        printerr("Unequal dimensions for: cross(a,b), sizes: a="*string(size(a))*", b="*string(size(b))*")");
    end
end

#########################################################################
# derivative ops
#########################################################################

# Applies a derivative prefix. wrt is the axis index
# sym_deriv(u_12, 1) -> D1_u_12
function sym_deriv(var, wrt)
    prefix = "D"*string(wrt)*"_";
    
    return symbols(prefix*string(var));
end

function sym_grad_op(u)
    result = Array{Basic,1}(undef,0);
    if typeof(u) <: Array
        d = config.dimension;
        rank = 0;
        if ndims(u) == 1 && length(u) > 1
            rank = 1;
        elseif ndims(u) == 2 
            rank = 2;
        end
        
        if rank == 0
            # result is a vector
            for i=1:d
                push!(result, sym_deriv(u[1], i));
            end
        elseif rank == 1
            # result is a tensor
            for i=1:d
                for j=1:d
                    push!(result, sym_deriv(u[i], j));
                end
            end
            reshape(result, d,d);
        elseif rank == 2
            # not yet ready
            printerr("unsupported operator, grad(tensor)");
            return nothing;
        end
    elseif typeof(u) == Basic
        # result is a vector
        d = config.dimension;
        for i=1:d
            push!(result, sym_deriv(u, i));
        end
    elseif typeof(u) <: Number
        return zeros(config.dimension);
    end
    
    return result;
end

function sym_div_op(u)
    result = Array{Basic,1}(undef,0);
    if typeof(u) <: Array
        d = config.dimension;
        rank = 0;
        if ndims(u) == 1 && length(u) > 1
            rank = 1;
        elseif ndims(u) == 2 
            rank = 2;
        end
        
        if rank == 0
            # Not allowed
            printerr("unsupported operator, div(scalar)");
            return nothing;
        elseif rank == 1
            # result is a scalar
            if d==1
                result = [sym_deriv(u[1], 1)];
            else
                ex = :(a+b);
                ex.args = [:+];
                for i=1:d
                    push!(ex.args, sym_deriv(u[i], i))
                end
                result = [Basic(ex)];
            end
        elseif rank == 2
            # not yet ready
            printerr("unsupported operator, div(tensor)");
            return nothing;
        end
    elseif typeof(u) <: Number
        # Not allowed
        printerr("unsupported operator, div(number)");
        return nothing;
    end
    
    return result;
end

function sym_curl_op(u)
    result = Array{Basic,1}(undef,0);
    if typeof(u) <: Array
        d = config.dimension;
        rank = 0;
        if ndims(u) == 1 && sz[1] > 1
            rank = 1;
        elseif ndims(u) == 2 
            rank = 2;
        end
        
        if rank == 0
            # Not allowed
            printerr("unsupported operator, curl(scalar)");
            return nothing;
        elseif rank == 1
            # result is a vector
            if d==1
                result = [sym_deriv(u[1], 1)];
            else
                #TODO
                printerr("curl not ready");
                return nothing;
            end
        elseif rank == 2
            # not yet ready
            printerr("unsupported operator, curl(tensor)");
            return nothing;
        end
    elseif typeof(u) <: Number
        # Not allowed
        printerr("unsupported operator, curl(number)");
        return nothing;
    end
    
    return result;
end

function sym_laplacian_op(u)
    # simply use the above ops
    return sym_div_op(sym_grad_op(u));
end
