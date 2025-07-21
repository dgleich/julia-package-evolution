#!/usr/bin/env julia

using JSON
using SparseArrays
using Graphs
using GraphPlayground
using Colors

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
function visualize_dependency_tree(package_name, depth=2; ego_net=false, exclude_packages=String[])
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
    
    # Get indices of packages to exclude
    exclude_indices = Set{Int}()
    for pkg in exclude_packages
        if haskey(package_to_index, pkg)
            push!(exclude_indices, package_to_index[pkg])
            println("Excluding package: $pkg (index: $(package_to_index[pkg]))")
        else
            println("Warning: Package $pkg not found in index, skipping exclusion")
        end
    end
    
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
    
    # Track node depths for coloring
    node_depths = Dict{Int, Int}()
    
    # If depth is -1, include all recursive dependencies
    if depth == -1
        deps_to_include = compute_recursive_dependencies(adj_list, package_idx)
        nodes_to_include = vcat([package_idx], collect(deps_to_include))
        
        # Compute node depths using BFS
        queue = Tuple{Int, Int}[(package_idx, 0)]  # (node, depth)
        visited = Set{Int}([package_idx])
        node_depths[package_idx] = 0
        
        while !isempty(queue)
            (node, current_depth) = popfirst!(queue)
            
            for dep in adj_list[node]
                if !(dep in visited)
                    push!(visited, dep)
                    node_depths[dep] = current_depth + 1
                    push!(queue, (dep, current_depth + 1))
                end
            end
        end
    else
        # BFS to get dependencies up to a certain depth
        deps_to_include = Set{Int}()
        queue = Tuple{Int, Int}[(package_idx, 0)]  # (node, depth)
        visited = Set{Int}([package_idx])
        node_depths[package_idx] = 0
        
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
                    node_depths[dep] = current_depth + 1
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
    
    # Filter out excluded packages
    if !isempty(exclude_indices)
        original_count = length(nodes_to_include)
        nodes_to_include = filter(idx -> !(idx in exclude_indices), nodes_to_include)
        excluded_count = original_count - length(nodes_to_include)
        println("Excluded $excluded_count packages from visualization")
    end
    
    println("Including $(length(nodes_to_include)) nodes in the visualization")
    
    # Create a mapping from original indices to graph indices
    orig_to_graph = Dict{Int, Int}()
    graph_to_orig = Dict{Int, Int}()
    for (i, idx) in enumerate(nodes_to_include)
        orig_to_graph[idx] = i
        graph_to_orig[i] = idx
    end
    
    # Create a graph with these nodes
    g = SimpleGraph(length(nodes_to_include))
    
    # Add edges to the graph
    for node in nodes_to_include
        if node <= length(adj_list)
            for dep in adj_list[node]
                if dep in nodes_to_include
                    # If ego_net is true, skip edges from the center package
                    if ego_net && node == package_idx
                        continue
                    end
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
    
    # Map node_depths to graph indices
    graph_node_depths = Dict{Int, Int}()
    for (orig_idx, depth) in node_depths
        if haskey(orig_to_graph, orig_idx)
            graph_node_depths[orig_to_graph[orig_idx]] = depth
        end
    end
    
    # Launch GraphPlayground for interactive exploration
    viz_type = ego_net ? "ego network" : "dependency tree"
    println("Launching GraphPlayground with $(nv(g)) nodes and $(ne(g)) edges ($viz_type)")
    playground(g; 
        link_options=(;distance=25, iterations=1),
        charge_options=(;strength=-100),
        labels=labels,
        initial_iterations=50)
    
    # Count the total number of recursive dependencies
    compute_recursive_dependencies(adj_list, package_idx)
    
    return g, labels, graph_node_depths
end

# Function to visualize graph with nodes colored by their depth
function vizgraph_with_depth(g, labels, node_depths)
    # Create a colormap for the depth levels
    max_depth = maximum(values(node_depths))
    colormap = range(colorant"orange", stop=colorant"lightblue", length=max_depth+1)
    
    # Create a node color array based on depth
    nodecolors = [colormap[get(node_depths, i, 1) + 1] for i in 1:nv(g)]
    
    # Launch GraphPlayground with custom settings and depth-based colors
    playground(g; 
        labels=labels,
        link_options=(;distance=25, iterations=1),
        charge_options=(;strength=-100),
        graphplot_options=(;node_color=nodecolors),
        initial_iterations=50)
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
    
    return sorted_deps, index_to_package
end

# Function to get dependency info for a package
function get_package_deps(package_name)
    println("Analyzing dependencies for $package_name...")
    g, labels, node_depths = visualize_dependency_tree(package_name, 2)
    sorted_deps, index_to_package = analyze_dependency_contributions(package_name)
    return g, labels, node_depths, sorted_deps, index_to_package
end

# Function to visualize ego network around a package
function visualize_ego_network(package_name, depth=2; exclude_packages=String[])
    println("Visualizing ego network for $package_name (depth=$depth)...")
    return visualize_dependency_tree(package_name, depth; ego_net=true, exclude_packages=exclude_packages)
end