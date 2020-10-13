#=
A Julia wrapper for pycachesim.
=#
module Jpycachesim

# Provided by backend
export pcs_load, pcs_store, pcs_get_cachesim_from_file, pcs_print_stats
# Provided here
export pcs_build_cache
# Structs
export Cache

cache = nothing;        # A cache is kept globally for convenience. Multiple caches can be managed externally.

# define structs
include("pcs_structs.jl");

function pcs_get_cachesim_from_file(filename)
    global cache = ccall((:get_cacheSim_from_file, "./cachesim/backend.so"), Ptr{Cache}, (Cstring,), filename);
    return cache;
end

function pcs_load(addr, len=1, c=cache)
    range = addr_range(addr,len);
    return ccall((:Cache__load, "./cachesim/backend.so"), Cint, (Ptr{Cache},addr_range), c, range);
end

function pcs_store(addr, len=1, c=cache)
    range = addr_range(addr,len);
    ccall((:Cache__store, "./cachesim/backend.so"), Cvoid, (Ptr{Cache},addr_range, Cint), c, range, 0);
end

function pcs_print_stats(c=cache)
    ccall((:printStats, "./cachesim/backend.so"), Cvoid, (Ptr{Cache},), c);
end

function pcs_build_cache(levels)
    # write to file, read from file, remove file
    file = open("cachesim/tmp_jpycachesim_cache_def","w");
    println(file, string(length(levels)));
    for i=1:(length(levels))
        line  = "name=L"*string(i);
        line *= ",sets="*string(Int(levels[i].sets));
        line *= ",ways="*string(Int(levels[i].ways));
        line *= ",cl_size="*string(Int(levels[i].cl_size));
        line *= ",replacement_policy_id="*string(Int(levels[i].replacement_policy_id));
        line *= ",write_back="*string(Int(levels[i].write_back));
        line *= ",write_allocate="*string(Int(levels[i].write_allocate));
        line *= ",subblock_size="*string(Int(levels[i].subblock_size));
        if i<length(levels)
            line *= ",load_from=L"*string(i+1);
            line *= ",store_to=L"*string(i+1);
        end
        
        print(file, line);
        if i<length(levels)
            print(file,"\n");
        end
    end
    close(file);
    
    return pcs_get_cachesim_from_file("cachesim/tmp_jpycachesim_cache_def");
end

end #module