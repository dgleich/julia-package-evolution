#!/usr/bin/env julia

using JSON
using SparseArrays
using Graphs
using GraphPlayground

"""
Visualize the dependency tree for a specific package using GraphPlayground.
"""

function read_smat(filename)
    open(filename, "r") do f
        # Read header line
        line = readline(f)
        parts = split(line)
        m = parse(Int, parts[1])
        n = parse(Int, parts[2])
        nnz = parse(Int, parts[3])
        
        # Initialize COO format
        rows = Int[]
        cols = Int[]
        vals = Int[]
        
        # Read data lines
        for _ in 1:nnz
            line = readline(f)
            parts = split(line)
            # Convert from 0-indexed to 1-indexed
            row = parse(Int, parts[1]) + 1
            col = parse(Int, parts[2]) + 1
            val = parse(Int, parts[3])
            push!(rows, row)
            push!(cols, col)
            push!(vals, val)
        end
        
        # Create and return sparse matrix
        return sparse(rows, cols, vals, m, n)
    end
end

# Create an adjacency list representation
function create_adjacency_list(A)
    n = size(A, 2)
    adj_list = [Int[] for _ in 1:n]
    
    # Iterate through columns of the CSC matrix which is efficient
    for j = 1:n
        # Get all nonzero entries in this column
        for i in nzrange(A, j)
            row = A.rowval[i]
            # A[row, j] = 1 means row depends on j
            # So j is a dependency of row
            push!(adj_list[row], j)
        end
    end
    
    return adj_list
end

# Create a visualization of the dependency tree
function visualize_dependency_tree(package_name, depth=2)
    # Load package index
    index_file = "combined_package_index.json"
    if !isfile(index_file)
        error("Combined package index file not found.")
    end
    
    index_data = open(index_file, "r") do io
        JSON.parse(io)
    end
    
    # Create mapping from package names to indices
    package_to_index = Dict{String, Int}()
    for (pkg, info) in index_data["package_metadata"]
        package_to_index[pkg] = info["index"]
    end
    
    # Create reverse mapping from indices to package names
    index_to_package = Dict{Int, String}()
    for (pkg, idx) in package_to_index
        index_to_package[idx] = pkg
    end
    
    # Check if the package exists
    if !haskey(package_to_index, package_name)
        error("$package_name not found in package index")
    end
    
    package_idx = package_to_index[package_name]
    println("$package_name index: $(package_idx)")
    
    # Get the latest matrix file
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    sort!(matrix_files)
    latest_matrix_file = matrix_files[end]
    println("Using matrix file: $(basename(latest_matrix_file))")
    
    # Read the matrix
    A = read_smat(latest_matrix_file)
    
    # Create adjacency list for efficient traversal
    adj_list = create_adjacency_list(A)
    
    # If depth is -1, include all recursive dependencies
    if depth == -1
        deps_to_include = compute_recursive_dependencies(adj_list, package_idx)
        nodes_to_include = vcat([package_idx], collect(deps_to_include))
    else
        # BFS to get dependencies up to a certain depth
        deps_to_include = Set{Int}()
        queue = Tuple{Int, Int}[(package_idx, 0)]  # (node, depth)
        visited = Set{Int}([package_idx])
        
        while !isempty(queue)
            (node, current_depth) = popfirst!(queue)
            
            if current_depth > depth
                continue
            end
            
            # Add dependencies at this level
            for dep in adj_list[node]
                push!(deps_to_include, dep)
                
                if !(dep in visited)
                    push!(visited, dep)
                    push!(queue, (dep, current_depth + 1))
                end
            end
        end
        
        # Convert to array and add the root package
        nodes_to_include = collect(deps_to_include)
        if !(package_idx in nodes_to_include)
            push!(nodes_to_include, package_idx)
        end
    end
    
    println("Including $(length(nodes_to_include)) nodes in the visualization")
    
    # Create a mapping from original indices to graph indices
    orig_to_graph = Dict{Int, Int}()
    for (i, idx) in enumerate(nodes_to_include)
        orig_to_graph[idx] = i
    end
    
    # Create a graph with these nodes
    g = SimpleGraph(length(nodes_to_include))
    
    # Add edges to the graph
    for node in nodes_to_include
        if node <= length(adj_list)
            for dep in adj_list[node]
                if dep in nodes_to_include
                    add_edge!(g, orig_to_graph[node], orig_to_graph[dep])
                end
            end
        end
    end
    
    # Prepare labels for the graph
    labels = String[]
    for i in 1:length(nodes_to_include)
        orig_idx = nodes_to_include[i]
        pkg_name = get(index_to_package, orig_idx, "Unknown")
        push!(labels, pkg_name)
    end
    
    # Launch GraphPlayground for interactive exploration
    # println("Launching GraphPlayground with $(nv(g)) nodes and $(ne(g)) edges")
    # playground(g; 
    #     link_options=(;iterations=5, strength=1.0, distance=50),
    #     labels=labels,
    #     initial_iterations=100)
    
    return g, labels
end

# Compute and analyze recursive dependencies
function compute_recursive_dependencies(adj_list, package_idx)
    n = length(adj_list)
    
    # Make sure the index is valid
    if package_idx > n || package_idx < 1
        return Set{Int}()
    end
    
    # Use a set to track visited nodes
    deps = Set{Int}()
    queue = Int[]
    
    # Add direct dependencies
    direct_deps = Set{Int}()
    for dep in adj_list[package_idx]
        push!(direct_deps, dep)
        push!(deps, dep)
        push!(queue, dep)
    end
    
    println("Direct dependencies: $(length(direct_deps))")
    
    # Process the queue to find all recursive dependencies
    while !isempty(queue)
        current = popfirst!(queue)
        if current <= length(adj_list)
            for dep in adj_list[current]
                if !(dep in deps)
                    push!(deps, dep)
                    push!(queue, dep)
                end
            end
        end
    end
    
    println("Total recursive dependencies: $(length(deps))")
    
    return deps
end

# Analyze which packages contribute the most to the dependency count
function analyze_dependency_contributions(package_name)
    # Load package index
    index_file = "combined_package_index.json"
    if !isfile(index_file)
        error("Combined package index file not found.")
    end
    
    index_data = open(index_file, "r") do io
        JSON.parse(io)
    end
    
    # Create mapping from package names to indices
    package_to_index = Dict{String, Int}()
    for (pkg, info) in index_data["package_metadata"]
        package_to_index[pkg] = info["index"]
    end
    
    # Create reverse mapping from indices to package names
    index_to_package = Dict{Int, String}()
    for (pkg, idx) in package_to_index
        index_to_package[idx] = pkg
    end
    
    # Check if the package exists
    if !haskey(package_to_index, package_name)
        error("$package_name not found in package index")
    end
    
    package_idx = package_to_index[package_name]
    
    # Get the latest matrix file
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    sort!(matrix_files)
    latest_matrix_file = matrix_files[end]
    
    # Read the matrix
    A = read_smat(latest_matrix_file)
    
    # Create adjacency list for efficient traversal
    adj_list = create_adjacency_list(A)
    
    # Get direct dependencies
    direct_deps = Set{Int}()
    for dep in adj_list[package_idx]
        push!(direct_deps, dep)
    end
    
    # Compute recursive dependencies for each direct dependency
    dep_contributions = Dict{Int, Int}()
    
    for dep in direct_deps
        # Count recursive dependencies of this direct dependency
        dep_deps = Set{Int}()
        queue = Int[dep]
        visited = Set{Int}([dep])
        
        while !isempty(queue)
            current = popfirst!(queue)
            if current <= length(adj_list)
                for subdep in adj_list[current]
                    push!(dep_deps, subdep)
                    if !(subdep in visited)
                        push!(visited, subdep)
                        push!(queue, subdep)
                    end
                end
            end
        end
        
        dep_contributions[dep] = length(dep_deps)
    end
    
    # Sort by number of dependencies
    sorted_deps = sort(collect(dep_contributions), by=x->x[2], rev=true)
    
    println("\nTop contributing dependencies:")
    for (i, (dep, count)) in enumerate(sorted_deps[1:min(30, length(sorted_deps))])
        pkg_name = get(index_to_package, dep, "Unknown")
        println("$i. $pkg_name: $count recursive dependencies")
    end
end
