#!/usr/bin/env julia

using JSON
using SparseArrays
using Graphs
using Dates
using GraphMakie.NetworkLayout

# Import functions from existing files
include("visualize_deps_tree.jl")
include("utilities.jl")

"""
Simple step-by-step temporal ecosystem visualization.
Works with any package, allows exclusions, and clusters by first appearance.
"""

# Helper functions (using existing utilities where possible)
function parse_matrix_date(filename)
    # Use existing function but convert back to string format
    date_obj = _extract_date_from_filename(filename)
    return date_obj !== nothing ? Dates.format(date_obj, "yyyy-mm") : nothing
end

# Step 1: Find when a package was first introduced
function find_package_introduction(package_name, package_to_index, index_to_package)
    if !haskey(package_to_index, package_name)
        error("$package_name not found in package index")
    end
    
    # Load package index to get first_seen date
    index_file = "combined_package_index.json"
    index_data = open(index_file, "r") do io
        JSON.parse(io)
    end
    
    if haskey(index_data["package_metadata"], package_name)
        first_seen = index_data["package_metadata"][package_name]["first_seen"]
        println("$package_name first introduced: $first_seen")
        return first_seen
    else
        error("$package_name metadata not found")
    end
end

# Step 2: Extract dependency subgraphs for each time slice (keep original indexing)
function extract_temporal_dependency_graphs(package_name, start_date=nothing; exclude_packages=String[], include_self=true)
    # Load package mappings using existing function
    indices = _load_package_index()
    package_to_index, index_to_package = indices.package_to_index, indices.index_to_package
    
    # Find package introduction date if not specified
    if start_date === nothing
        start_date = find_package_introduction(package_name, package_to_index, index_to_package)
    end
    
    package_idx = package_to_index[package_name]
    println("$package_name index: $package_idx, starting from: $start_date")
    
    # Get exclusion indices
    exclude_indices = Set{Int}()
    for pkg in exclude_packages
        if haskey(package_to_index, pkg)
            push!(exclude_indices, package_to_index[pkg])
            println("Excluding: $pkg")
        end
    end
    
    # Get matrix files from start date onwards
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    sort!(matrix_files)
    
    # Filter matrices from start date
    relevant_matrices = filter(matrix_files) do file
        date_str = parse_matrix_date(file)
        date_str !== nothing && date_str >= start_date
    end
    
    println("Processing $(length(relevant_matrices)) matrices from $(parse_matrix_date(relevant_matrices[1]))")
    
    # Extract dependency subgraphs for each time slice
    temporal_graphs = Dict{String, SparseMatrixCSC{Int, Int}}()
    temporal_deps_sets = Dict{String, Set{Int}}()
    
    for matrix_file in relevant_matrices
        date_str = parse_matrix_date(matrix_file)
        println("Processing $date_str...")
        
        # Read full matrix
        A = read_smat(matrix_file)
        adj_list = create_adjacency_list(A)
        
        # Get all recursive dependencies using existing function
        deps = compute_recursive_dependencies(adj_list, package_idx)
        
        # Remove excluded packages
        deps = setdiff(deps, exclude_indices)
        
        # Include or exclude the package itself based on option
        if include_self
            deps_final = copy(deps)
            push!(deps_final, package_idx)
        else
            deps_final = deps
        end
        
        # Create subgraph adjacency matrix (keep original indexing)
        n = size(A, 1)
        subgraph_A = spzeros(Int, n, n)
        
        # Copy edges within the dependency set
        for i in deps_final
            if i <= length(adj_list)
                for j in adj_list[i]
                    if j in deps_final
                        subgraph_A[i, j] = 1
                    end
                end
            end
        end
        
        temporal_graphs[date_str] = subgraph_A
        temporal_deps_sets[date_str] = deps_final
        println("  Dependencies: $(length(deps)), Edges: $(nnz(subgraph_A))")
    end
    
    return temporal_graphs, temporal_deps_sets, package_idx, package_to_index, index_to_package
end

# Step 3: Form union graph using OR of adjacency matrices
function create_union_dependency_graph(temporal_graphs, temporal_deps_sets, package_idx, package_to_index, index_to_package)
    println("\\nCreating union graph using OR of adjacency matrices...")
    
    # Find union of all dependencies across time
    all_deps_union = Set{Int}()
    for (date, deps) in temporal_deps_sets
        union!(all_deps_union, deps)
    end
    
    println("Total unique dependencies across all time: $(length(all_deps_union))")
    
    # Get matrix size from first temporal graph
    first_graph = first(values(temporal_graphs))
    n = size(first_graph, 1)
    
    # Create union adjacency matrix using OR operation
    union_A = spzeros(Int, n, n)
    
    for (date, A_slice) in temporal_graphs
        # Element-wise OR (max since we're using 0/1)
        union_A = max.(union_A, A_slice)
    end
    
    println("Union adjacency matrix: $(n)x$(n), $(nnz(union_A)) edges")
    
    # Now create reindexed subgraph with only relevant nodes
    deps_list = collect(all_deps_union)
    sort!(deps_list)  # Consistent ordering
    
    orig_to_graph = Dict{Int, Int}()
    graph_to_orig = Dict{Int, Int}()
    
    for (i, orig_idx) in enumerate(deps_list)
        orig_to_graph[orig_idx] = i
        graph_to_orig[i] = orig_idx
    end
    
    # Extract subgraph with only relevant nodes
    m = length(deps_list)
    union_subgraph = spzeros(Int, m, m)
    
    for (i, orig_i) in enumerate(deps_list)
        for (j, orig_j) in enumerate(deps_list)
            if union_A[orig_i, orig_j] == 1
                union_subgraph[i, j] = 1
            end
        end
    end
    
    # Convert to Graphs.jl format (use SimpleDiGraph for directed dependencies)
    union_graph = SimpleDiGraph(union_subgraph)
    
    # Create labels
    #labels = [get(index_to_package, orig_idx, "Unknown") for orig_idx in deps_list]
    labels = index_to_package
    
    println("Union subgraph created: $(nv(union_graph)) nodes, $(ne(union_graph)) edges")
    
    return union_graph, union_A, labels, orig_to_graph, graph_to_orig, deps_list, all_deps_union
end

# Cluster packages by first appearance in GLMakie's dependency list
function cluster_by_first_appearance_in_deps(deps_list, temporal_deps_sets, index_to_package)
    println("\\nClustering packages by first appearance in dependency list...")
    
    # Sort time periods to process chronologically
    time_periods = sort(collect(keys(temporal_deps_sets)))
    
    # Track when each package first appears in the dependency list
    first_appearance = Dict{Int, String}()
    
    for period in time_periods
        deps_in_period = temporal_deps_sets[period]
        
        for dep_idx in deps_in_period
            # If we haven't seen this dependency before, record its first appearance
            if !haskey(first_appearance, dep_idx)
                first_appearance[dep_idx] = period
            end
        end
    end
    
    # Create clusters based on first appearance time in dependency list
    date_to_cluster = Dict{String, Int}()
    cluster_id = 1
    
    clusters = Int[]
    
    for orig_idx in deps_list
        if haskey(first_appearance, orig_idx)
            first_seen_in_deps = first_appearance[orig_idx]
            
            if !haskey(date_to_cluster, first_seen_in_deps)
                date_to_cluster[first_seen_in_deps] = cluster_id
                cluster_id += 1
            end
            
            push!(clusters, date_to_cluster[first_seen_in_deps])
        else
            # Unknown package gets cluster 1 (shouldn't happen if deps_list is correct)
            push!(clusters, 1)
        end
    end
    
    println("Created $(cluster_id-1) clusters based on first appearance in dependency list")
    
    # Print cluster information
    for (date, cluster_id) in sort(collect(date_to_cluster), by=x->x[1])
        count = sum(clusters .== cluster_id)
        pkg_names = [get(index_to_package, deps_list[i], "Unknown") 
                    for i in 1:length(clusters) if clusters[i] == cluster_id]
        println("Cluster $cluster_id ($date): $count packages")
        if count <= 5  # Show package names for small clusters
            #println("  Packages: $(join(pkg_names, \", \"))")
        end
    end
    
    return clusters, date_to_cluster
end

# Create colors for clusters, assigning unique colors to large clusters and black to small ones
function create_cluster_colors(clusters, min_cluster_size=5)
    println("Creating colors for clusters (min size: $min_cluster_size)...")
    
    # Count cluster sizes
    cluster_counts = Dict{Int, Int}()
    for cluster_id in clusters
        cluster_counts[cluster_id] = get(cluster_counts, cluster_id, 0) + 1
    end
    
    # Define a palette of distinct colors for large clusters
    color_palette = [
        "#1f77b4",  # blue
        "#ff7f0e",  # orange  
        "#2ca02c",  # green
        "#d62728",  # red
        "#9467bd",  # purple
        "#8c564b",  # brown
        "#e377c2",  # pink
        "#7f7f7f",  # gray
        "#bcbd22",  # olive
        "#17becf",  # cyan
        "#aec7e8",  # light blue
        "#ffbb78",  # light orange
        "#98df8a",  # light green
        "#ff9896",  # light red
        "#c5b0d5",  # light purple
        "#c49c94",  # light brown
        "#f7b6d3",  # light pink
        "#c7c7c7",  # light gray
        "#dbdb8d",  # light olive
        "#9edae5"   # light cyan
    ]
    
    # Find large clusters and assign colors
    large_clusters = Int[]
    for (cluster_id, count) in cluster_counts
        if count >= min_cluster_size
            push!(large_clusters, cluster_id)
        end
    end
    sort!(large_clusters)  # Consistent ordering
    
    cluster_to_color = Dict{Int, String}()
    for (i, cluster_id) in enumerate(large_clusters)
        cluster_to_color[cluster_id] = color_palette[((i-1) % length(color_palette)) + 1]
    end
    
    # Create color list for all nodes
    node_colors = String[]
    for cluster_id in clusters
        if haskey(cluster_to_color, cluster_id)
            push!(node_colors, cluster_to_color[cluster_id])
        else
            push!(node_colors, "#000000")  # black for small clusters
        end
    end
    
    println("Assigned unique colors to $(length(large_clusters)) large clusters, " *
            "black to $(length(cluster_counts) - length(large_clusters)) small clusters")
    
    return node_colors, cluster_to_color
end

# Step 4: Generate layout coordinates using NetworkLayout
function compute_layout_coordinates(union_graph, labels; layout_algorithm=:spring)
    println("\\nComputing layout coordinates using $layout_algorithm...")
    
    # Available layouts in NetworkLayout that work well with GraphMakie:
    # :spring, :stress, :sfdp, :circular, :shell, :spectral
    
    if layout_algorithm == :spring
        #pos = NetworkLayout.spring(union_graph, iterations=1000, C=2.0, k=1.0)
        pos = NetworkLayout.spring(union_graph)
    elseif layout_algorithm == :stress
        pos = stress_layout(union_graph, iterations=1000)
    elseif layout_algorithm == :sfdp
        pos = sfdp_layout(union_graph, K=1.0, C=0.2)
    elseif layout_algorithm == :circular
        pos = circular_layout(union_graph)
    elseif layout_algorithm == :shell
        pos = shell_layout(union_graph)
    elseif layout_algorithm == :spectral
        pos = spectral_layout(union_graph)
    else
        @warn "Unknown layout algorithm $layout_algorithm, using spring layout"
        pos = spring_layout(union_graph, iterations=1000, C=2.0, k=1.0)
    end
    
    # Extract x, y coordinates
    pos_x = [p[1] for p in pos]
    pos_y = [p[2] for p in pos]
    
    println("Layout computed: $(length(pos_x)) node positions")
    
    return pos_x, pos_y, pos
end

# Main function to run steps 1-4
function analyze_package_ecosystem(package_name, start_date=nothing; exclude_packages=String[], include_self=true, layout_algorithm=:spring)
    println("=== Analyzing $package_name Ecosystem ===")
    
    # Step 1 & 2: Extract temporal dependency graphs
    temporal_graphs, temporal_deps_sets, package_idx, package_to_index, index_to_package = extract_temporal_dependency_graphs(
        package_name, start_date; exclude_packages=exclude_packages, include_self=include_self)
    
    # Step 3: Create union graph using OR of adjacency matrices
    union_graph, union_A, labels, orig_to_graph, graph_to_orig, deps_list, all_deps_union = create_union_dependency_graph(
        temporal_graphs, temporal_deps_sets, package_idx, package_to_index, index_to_package)
    
    # Step 4: Compute layout coordinates
    pos_x, pos_y, positions = compute_layout_coordinates(union_graph, labels; layout_algorithm=layout_algorithm)
    
    # Create clusters by first appearance in dependency list
    clusters, date_to_cluster = cluster_by_first_appearance_in_deps(deps_list, temporal_deps_sets, index_to_package)
    
    # Create colors for clusters
    node_colors, cluster_to_color = create_cluster_colors(clusters)
    
    # Return all data for further processing
    return Dict(
        "package_name" => package_name,
        "package_idx" => package_idx,
        "temporal_graphs" => temporal_graphs,
        "temporal_deps_sets" => temporal_deps_sets,
        "union_graph" => union_graph,
        "union_A" => union_A,
        "labels" => labels,
        "orig_to_graph" => orig_to_graph,
        "graph_to_orig" => graph_to_orig,
        "deps_list" => deps_list,
        "all_deps_union" => all_deps_union,
        "clusters" => clusters,
        "date_to_cluster" => date_to_cluster,
        "node_colors" => node_colors,
        "cluster_to_color" => cluster_to_color,
        "package_to_index" => package_to_index,
        "index_to_package" => index_to_package,
        "pos_x" => pos_x,
        "pos_y" => pos_y,
        "positions" => positions,
        "layout_algorithm" => layout_algorithm
    )
end

# Helper function to show temporal statistics
function show_temporal_stats(results)
    temporal_deps_sets = results["temporal_deps_sets"]
    
    println("\\n=== Temporal Statistics ===")
    periods = sort(collect(keys(temporal_deps_sets)))
    
    for period in periods
        count = length(temporal_deps_sets[period])
        println("$period: $count dependencies")
    end
    
    println("\\nCluster Information:")
    clusters = results["clusters"]
    labels = results["labels"]
    date_to_cluster = results["date_to_cluster"]
    
    for (date, cluster_id) in sort(collect(date_to_cluster), by=x->x[1])
        count = sum(clusters .== cluster_id)
        println("Cluster $cluster_id ($date): $count packages")
    end
end

# form a subgraph from a matrix and labels
function subgraph(mat, results) 
    lbls = results["labels"]
    ei, ej = findnz(mat)[1:2]
    ids = union(ei, ej)
    labels = map(id -> lbls[id], ids)
    # relabel the graph 
    id2small = Dict{Int,Int}(ids .=> 1:length(ids))
    si = map(id -> id2small[id], ei)
    sj = map(id -> id2small[id], ej)
    sm = sparse(si, sj, 1, length(ids), length(ids))
    g = SimpleDiGraph(sm) 
    return g, labels
end 

# Example usage functions
function analyze_glmakie(; exclude_packages=String[], include_self=true, layout_algorithm=:spring)
    return analyze_package_ecosystem("GLMakie"; exclude_packages=exclude_packages, include_self=include_self, layout_algorithm=layout_algorithm)
end

function analyze_plots(; exclude_packages=String[], include_self=true, layout_algorithm=:spring)
    return analyze_package_ecosystem("Plots"; exclude_packages=exclude_packages, include_self=include_self, layout_algorithm=layout_algorithm)
end