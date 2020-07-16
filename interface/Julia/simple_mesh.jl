# A set of simple mesh makers for testing
export simple_line_mesh, simple_quad_mesh, simple_hex_mesh

#=
# Conveniently builds a uniform unit interval mesh.
# Simple just to get things working.
=#
function simple_line_mesh(nx)
    ord = config.basis_order_min;
    refel = build_refel(1, ord, 2, LOBATTO);
    Nv = nx;                    # number of vertex nodes
    N = (nx-1)*ord + 1;         # number of total nodes
    nel = nx-1;                 # number of elements
    Np = refel.Np;              # number of nodes per element
    el = zeros(Int, nel, 2);    # element vertex maps
    xv = zeros(Nv,1);           # coordinates of vertices
    x = zeros(N,1);             # coordinates of all nodes
    bdry = [];                  # index(in x) of boundary nodes for each BID
    bids = [1];
    loc2glb = zeros(Int, nel,Np)# local to global index map for each element's nodes
    h = 1/(nx-1);               # unit interval uniformly divided
    
    # vertex nodes are ordered 
    for j=1:nx
        xv[j,1] = (j-1)*h;
    end
    
    # Elements are ordered the same way
    for ei=1:(nx-1)
        x1 = (ei-1)*h; # left vertex
        for ni=1:Np-1
            gi = (ei-1)*(Np-1) + ni; # global index of this node
            x[gi,1] = x1 .+ h*0.5 .* (refel.r[ni] + 1); # coordinates of this node
            loc2glb[ei,ni] = gi; # local to global map
        end
        loc2glb[ei,Np] = ei*(Np-1) + 1;
        
        el[ei,1] = ei;
        el[ei,2] = ei+1;
    end
    # The last node was left out
    x[N] = 1.0;
    
    # indices are in order
    ind = Array(1:Nv);
    
    # boundary is simple
    bdry = [1 N];
    
    mesh = MeshData(Nv, xv, ind, nel, el, ones(nel), 2*ones(nel)); # MeshData struct
    grid = Grid(x, bdry, bids);
    
    return (mesh, refel, grid, loc2glb);
end

#=
# Conveniently builds a square, uniform, unit quad mesh.
# Simple just to get things working.
=#
function simple_quad_mesh(nx)
    ord = config.basis_order_min;
    refel = build_refel(2, ord, 4, LOBATTO);
    Nv = nx*nx;                 # number of vertex nodes
    N = (nx-1)*ord + 1;
    N = N*N;                    # number of total nodes
    nel = (nx-1)*(nx-1);        # number of elements
    Np = refel.Np;              # number of nodes per element
    el = zeros(Int, nel, 4);    # element vertex maps
    xv = zeros(Nv,2);           # coordinates of vertices
    x = zeros(N,2);             # coordinates of all nodes
    bdry = [];                  # index(in x) of boundary nodes for each BID
    bids = [1];
    loc2glb = zeros(Int, nel,Np)# local to global index map for each element's nodes
    h = 1/(nx-1);               # unit square uniformly divided
    
    # vertex nodes are ordered along x then y
    for j=1:nx
        for i=1:nx
            k = i + (j-1)*nx;
            xv[k,1] = (i-1)*h;
            xv[k,2] = (j-1)*h;
        end
    end
    
    # Elements are ordered along x then y
    n1d = ord+1;
    rowsize = (nx-1)*(n1d-1) + 1;
    for j=1:(nx-1)
        for i=1:(nx-1)
            ei = i + (j-1)*(nx-1); # element index
            x1 = [(i-1)*h ; (j-1)*h]; # southwest corner 
            for jj=1:n1d-1
                row = (j-1)*(n1d-1) + jj;
                for ii=1:n1d-1
                    gi = (row-1)*rowsize + (i-1)*(n1d-1) + ii; # global index of this node
                    li = (jj-1)*n1d + ii; # local index of this node
                    x[gi,:] = x1 .+ h*0.5 .* (refel.r[li,:] + [1; 1]); # coordinates of this node
                    loc2glb[ei,li] = gi; # local to global map
                end
                loc2glb[ei,jj*n1d] = (row-1)*rowsize + (i-1)*(n1d-1) + n1d; # last in local x
            end
            row = j*(n1d-1)+1;
            for ii=1:n1d
                loc2glb[ei, n1d*(n1d-1)+ii] = ((row-1)*rowsize + (i-1)*(n1d-1)) + ii; # last in local y
            end
            
            el[ei,1] = i + (j-1)*nx;
            el[ei,2] = i + (j-1)*nx + 1;
            el[ei,3] = i + (j)*nx;
            el[ei,4] = i + (j)*nx + 1;
        end
        # The last node on the row was not set
        x1 = [(nx-2)*h ; (j-1)*h]; # southwest corner of last element
        for jj=1:n1d-1
            li = jj*n1d; # local index of this node
            x[((j-1)*(n1d-1)+jj)*rowsize,:] = x1 .+ h*0.5 .* (refel.r[li,:] + [1; 1]); # coordinates of this node
        end
    end
    # The top row was not set
    rowstart = ((n1d-1)*(nx-1))*rowsize;
    for i=1:(nx-1)
        x1 = [(i-1)*h ; (nx-2)*h]; # southwest corner of top element
        for ii=1:n1d-1
            gi = rowstart + (i-1)*(n1d-1) + ii;
            li = (n1d-1)*n1d + ii; # local index of this node
            x[gi, :] = x1 .+ h*0.5 .* (refel.r[li,:] + [1; 1]); # coordinates of this node
        end
    end
    # corner
    x[N,:] = [1; 1];
    
    # indices are in order
    ind = Array(1:Nv);
    
    # boundaries
    bdry = zeros(1, rowsize*4 - 4);
    for i=1:rowsize
        bdry[1,i] = i; # bottom
        bdry[1,i+rowsize] = N-rowsize + i; # top
        if i > 1 && i < rowsize
            bdry[1, i-1 + rowsize*2] = (i-1)*rowsize + 1; # left
            bdry[1, i-3 + rowsize*3] = i*rowsize; # right
        end
    end
    
    mesh = MeshData(Nv, xv, ind, nel, el, 3*ones(nel), 4*ones(nel)); # MeshData struct
    grid = Grid(x, bdry, bids);
    
    return (mesh, refel, grid, loc2glb);
end

#=
# Conveniently builds a uniform, unit cube, hex mesh.
# Simple just to get things working.
=#
function simple_hex_mesh(nx)
    ord = config.basis_order_min;
    refel = build_refel(3, ord, 6, LOBATTO);
    Nv = nx*nx*nx;                 # number of vertex nodes
    N = (nx-1)*ord + 1;
    N = N*N*N;                    # number of total nodes
    nel = (nx-1)*(nx-1)*(nx-1);        # number of elements
    Np = refel.Np;              # number of nodes per element
    el = zeros(Int, nel, 8);    # element vertex maps
    xv = zeros(Nv,3);           # coordinates of vertices
    x = zeros(N,3);             # coordinates of all nodes
    bdry = [];                  # index(in x) of boundary nodes for each BID
    bids = [1];
    loc2glb = zeros(Int, nel, Np)# local to global index map for each element's nodes
    h = 1/(nx-1);               # unit square uniformly divided
    
    # Start with a 2d quad mesh
    (mesh2d, refel2d, grid2d, loc2glb2d) = simple_quad_mesh(nx);
    
    # vertex nodes are ordered along x then y then z
    for k=1:nx
        for j=1:nx
            for i=1:nx
                ind = i + (j-1)*nx + (k-1)*nx*nx;
                xv[ind,1] = (i-1)*h;
                xv[ind,2] = (j-1)*h;
                xv[ind,3] = (k-1)*h;
            end
        end
    end
    
    # Use 2d quad mesh to build hex mesh nodes
    n1d = ord+1;
    rowsize = (nx-1)*(n1d-1) + 1;
    slicesize = rowsize*(nx-1)*(n1d-1) + rowsize;
    zvals = grid2d.allnodes[1:rowsize,1];
    for k=1:rowsize;
        range = ((k-1)*slicesize+1):(k*slicesize);
        x[range, :] = [grid2d.allnodes  zvals[k].*ones(slicesize)];
    end
    
    # Elements are ordered along x then y then z
    for k=1:(nx-1)
        for j=1:(nx-1) # element indices
            for i=1:(nx-1)
                ei = i + (j-1)*(nx-1) + (k-1)*(nx-1)*(nx-1); # element index
                for kk=1:n1d-1
                    slice = (k-1)*(n1d-1) + kk;
                    for jj=1:n1d-1 # elemental node indices
                        row = (j-1)*(n1d-1) + jj;
                        for ii=1:n1d-1
                            gi = (slice-1)*slicesize + (row-1)*rowsize + (i-1)*(n1d-1) + ii; # global index of this node
                            li = (kk-1)*n1d*n1d + (jj-1)*n1d + ii; # local index of this node
                            loc2glb[ei,li] = gi; # local to global map
                        end
                        loc2glb[ei,(kk-1)*n1d*n1d + jj*n1d] = (slice-1)*slicesize + (row-1)*rowsize + (i-1)*(n1d-1) + n1d; # last in local x
                    end
                    
                    row = j*(n1d-1)+1;
                    for ii=1:n1d
                        loc2glb[ei, (kk-1)*n1d*n1d + n1d*(n1d-1)+ii] = ((slice-1)*slicesize + (row-1)*rowsize + (i-1)*(n1d-1)) + ii; # last in local y
                    end
                end
                
                slice = k*(n1d-1)+1;  # last in local z
                for jj=1:n1d-1
                    row = (j-1)*(n1d-1) + jj;
                    for ii=1:n1d-1
                        gi = (slice-1)*slicesize + (row-1)*rowsize + (i-1)*(n1d-1) + ii; # global index of this node
                        li = (n1d-1)*n1d*n1d + (jj-1)*n1d + ii; # local index of this node
                        loc2glb[ei,li] = gi; # local to global map
                    end
                    loc2glb[ei,(n1d-1)*n1d*n1d + jj*n1d] = (slice-1)*slicesize + (row-1)*rowsize + (i-1)*(n1d-1) + n1d; # last in local x
                end
                row = j*(n1d-1)+1;
                for ii=1:n1d
                    loc2glb[ei, (n1d-1)*n1d*n1d + n1d*(n1d-1)+ii] = ((slice-1)*slicesize + (row-1)*rowsize + (i-1)*(n1d-1)) + ii; # last in local y
                end
                
                el[ei,1] = i + (j-1)*nx + (k-1)*nx*nx;
                el[ei,2] = i + (j-1)*nx + (k-1)*nx*nx + 1;
                el[ei,3] = i + (j)*nx + (k-1)*nx*nx;
                el[ei,4] = i + (j)*nx + (k-1)*nx*nx + 1;
                el[ei,5] = i + (j-1)*nx + (k)*nx*nx;
                el[ei,6] = i + (j-1)*nx + (k)*nx*nx + 1;
                el[ei,7] = i + (j)*nx + (k)*nx*nx;
                el[ei,8] = i + (j)*nx + (k)*nx*nx + 1;
            end
        end
    end
    
    # indices are in order
    indexorder = Array(1:Nv);
    
    # boundaries
    N1d = (nx-1)*ord + 1;
    bdry = zeros(1, N - (N1d-2)*(N1d-2)*(N1d-2));
    ind = 1;
    for i=1:slicesize
        bdry[1, i] = i; # z=0
        bdry[1, i+slicesize] = N-i+1; # z=1
    end
    ind = 2*slicesize + 1;
    for j=2:rowsize-1
        offset = (j-1)*slicesize;
        for i=1:rowsize
            bdry[1,ind] = offset + i; # bottom
            bdry[1,ind+1] = offset + slicesize-rowsize + i; # top
            ind += 2;
            if i > 1 && i < rowsize
                bdry[1, ind] = offset + (i-1)*rowsize + 1; # left
                bdry[1, ind + 1] = offset + i*rowsize; # right
                ind += 2;
            end
        end
    end
    
    mesh = MeshData(Nv, xv, indexorder, nel, el, 5*ones(nel), 8*ones(nel)); # MeshData struct
    grid = Grid(x, bdry, bids);
    
    return (mesh, refel, grid, loc2glb);
end