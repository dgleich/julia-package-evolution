#!/usr/bin/env julia

using JSON
using SparseArrays
using Graphs
using GraphPlayground
using Colors
using Statistics
using LinearAlgebra
using Dates

"""
Analyze the evolution of GLMakie's ecosystem over time.
This script:
1. Extracts all dependencies GLMakie ever had across all time periods
2. Creates a combined graph of all dependencies ever
3. Generates stable layout coordinates for visualization
4. Runs Louvain clustering to identify ecosystem components
5. Creates temporal visualization showing evolution
"""

# Read SMAT file format
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

# Create adjacency list from sparse matrix
function create_adjacency_list(A)
    n = size(A, 2)
    adj_list = [Int[] for _ in 1:n]
    
    for j = 1:n
        for i in nzrange(A, j)
            row = A.rowval[i]
            push!(adj_list[row], j)
        end
    end
    
    return adj_list
end

# Compute all recursive dependencies for a package
function compute_all_recursive_dependencies(adj_list, package_idx)
    if package_idx > length(adj_list) || package_idx < 1
        return Set{Int}()
    end
    
    deps = Set{Int}()
    queue = Int[]
    
    # Add direct dependencies
    for dep in adj_list[package_idx]
        push!(deps, dep)
        push!(queue, dep)
    end
    
    # Process queue for recursive dependencies
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
    
    return deps
end

# Parse date from matrix filename
function parse_matrix_date(filename)
    basename_file = basename(filename)
    date_match = match(r"adj_(\d{4}-\d{2})\.smat", basename_file)
    return date_match !== nothing ? date_match.captures[1] : nothing
end

# Load package index
function load_package_index()
    index_file = "combined_package_index.json"
    if !isfile(index_file)
        error("Combined package index file not found.")
    end
    
    index_data = open(index_file, "r") do io
        JSON.parse(io)
    end
    
    # Create mappings
    package_to_index = Dict{String, Int}()
    index_to_package = Dict{Int, String}()
    
    for (pkg, info) in index_data["package_metadata"]
        idx = info["index"]
        package_to_index[pkg] = idx
        index_to_package[idx] = pkg
    end
    
    return package_to_index, index_to_package
end

# Extract GLMakie dependencies across all time periods
function extract_glmakie_temporal_dependencies()
    package_to_index, index_to_package = load_package_index()
    
    # Check if GLMakie exists
    if !haskey(package_to_index, "GLMakie")
        error("GLMakie not found in package index")
    end
    
    glmakie_idx = package_to_index["GLMakie"]
    println("GLMakie index: $glmakie_idx")
    
    # Get all matrix files from GLMakie introduction onwards
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    sort!(matrix_files)
    
    # Filter to start from GLMakie introduction (2018-12)
    glmakie_matrices = filter(matrix_files) do file
        date_str = parse_matrix_date(file)
        date_str !== nothing && date_str >= "2018-12"
    end
    
    println("Processing $(length(glmakie_matrices)) matrices from $(parse_matrix_date(glmakie_matrices[1])) to $(parse_matrix_date(glmakie_matrices[end]))")
    
    # Track dependencies over time
    temporal_deps = Dict{String, Set{Int}}()
    all_deps_ever = Set{Int}()
    
    for matrix_file in glmakie_matrices
        date_str = parse_matrix_date(matrix_file)
        println("Processing $date_str...")
        
        # Read matrix and create adjacency list
        A = read_smat(matrix_file)
        adj_list = create_adjacency_list(A)
        
        # Get all recursive dependencies for GLMakie
        deps = compute_all_recursive_dependencies(adj_list, glmakie_idx)
        
        # Store temporal data
        temporal_deps[date_str] = deps
        union!(all_deps_ever, deps)
        
        println("  Dependencies: $(length(deps))")
    end
    
    # Add GLMakie itself to the dependency set
    push!(all_deps_ever, glmakie_idx)
    
    println("\\nTotal unique dependencies ever: $(length(all_deps_ever))")
    
    return temporal_deps, all_deps_ever, glmakie_idx, package_to_index, index_to_package
end

# Create combined graph of all dependencies ever
function create_combined_dependency_graph(all_deps_ever, glmakie_idx, package_to_index, index_to_package)
    println("Creating combined dependency graph...")
    
    # Get the latest matrix to extract edge information
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    sort!(matrix_files)
    latest_matrix_file = matrix_files[end]
    
    # Read the latest matrix
    A = read_smat(latest_matrix_file)
    adj_list = create_adjacency_list(A)
    
    # Create node mapping for the subgraph
    deps_list = collect(all_deps_ever)
    sort!(deps_list)
    
    orig_to_graph = Dict{Int, Int}()
    graph_to_orig = Dict{Int, Int}()
    
    for (i, orig_idx) in enumerate(deps_list)
        orig_to_graph[orig_idx] = i
        graph_to_orig[i] = orig_idx
    end
    
    # Create graph with only the relevant nodes
    g = SimpleGraph(length(deps_list))
    
    # Add edges within the dependency subgraph
    for node in deps_list
        if node <= length(adj_list)
            for dep in adj_list[node]
                if dep in all_deps_ever
                    add_edge!(g, orig_to_graph[node], orig_to_graph[dep])
                end
            end
        end
    end
    
    # Create labels
    labels = [get(index_to_package, orig_idx, "Unknown") for orig_idx in deps_list]
    
    println("Combined graph: $(nv(g)) nodes, $(ne(g)) edges")
    
    return g, labels, orig_to_graph, graph_to_orig, deps_list
end

# Generate stable layout using NetworkLayout or similar
function generate_stable_layout(g, labels)
    println("Generating stable layout coordinates...")
    
    # Use a simple spring layout for now
    # In practice, you might want to use NetworkLayout.jl or GraphPlot.jl
    n = nv(g)
    
    # Initialize random positions
    pos_x = randn(n)
    pos_y = randn(n)
    
    # Simple spring layout iterations
    for iter in 1:100
        # Forces between connected nodes (attraction)
        for edge in edges(g)
            i, j = src(edge), dst(edge)
            dx = pos_x[j] - pos_x[i]
            dy = pos_y[j] - pos_y[i]
            dist = sqrt(dx^2 + dy^2) + 1e-6
            force = 0.1 * (dist - 2.0)
            
            pos_x[i] += force * dx / dist * 0.5
            pos_y[i] += force * dy / dist * 0.5
            pos_x[j] -= force * dx / dist * 0.5
            pos_y[j] -= force * dy / dist * 0.5
        end
        
        # Repulsion between all nodes
        for i in 1:n
            for j in (i+1):n
                dx = pos_x[j] - pos_x[i]
                dy = pos_y[j] - pos_y[i]
                dist = sqrt(dx^2 + dy^2) + 1e-6
                force = 50.0 / (dist^2)
                
                pos_x[i] -= force * dx / dist * 0.1
                pos_y[i] -= force * dy / dist * 0.1
                pos_x[j] += force * dx / dist * 0.1
                pos_y[j] += force * dy / dist * 0.1
            end
        end
        
        # Damping
        pos_x .*= 0.95
        pos_y .*= 0.95
    end
    
    return pos_x, pos_y
end

# Run Louvain clustering (simplified implementation)
function run_louvain_clustering(g)
    println("Running Louvain clustering...")
    
    # For now, use a simple connected components approach
    # In practice, you'd use a proper Louvain implementation
    components = connected_components(g)
    
    # Create cluster assignment
    cluster_assignment = zeros(Int, nv(g))
    for (cluster_id, component) in enumerate(components)
        for node in component
            cluster_assignment[node] = cluster_id
        end
    end
    
    println("Found $(length(components)) clusters")
    
    return cluster_assignment, components
end

# Create temporal visualization data
function create_temporal_visualization_data(temporal_deps, all_deps_ever, glmakie_idx, 
                                           orig_to_graph, graph_to_orig, pos_x, pos_y, 
                                           cluster_assignment, index_to_package)
    println("Creating temporal visualization data...")
    
    # Sort time periods
    time_periods = sort(collect(keys(temporal_deps)))
    
    # Create visualization data for each time period
    temporal_data = Dict{String, Any}()
    
    for period in time_periods
        deps_in_period = temporal_deps[period]
        
        # Include GLMakie
        nodes_in_period = copy(deps_in_period)
        push!(nodes_in_period, glmakie_idx)
        
        # Map to graph indices
        graph_nodes = [orig_to_graph[idx] for idx in nodes_in_period if haskey(orig_to_graph, idx)]
        
        # Extract positions and clusters for this period
        period_pos_x = [pos_x[i] for i in graph_nodes]
        period_pos_y = [pos_y[i] for i in graph_nodes]
        period_clusters = [cluster_assignment[i] for i in graph_nodes]
        period_labels = [get(index_to_package, graph_to_orig[i], "Unknown") for i in graph_nodes]
        
        temporal_data[period] = Dict(
            "nodes" => graph_nodes,
            "pos_x" => period_pos_x,
            "pos_y" => period_pos_y,
            "clusters" => period_clusters,
            "labels" => period_labels,
            "count" => length(graph_nodes)
        )
        
        println("$period: $(length(graph_nodes)) nodes")
    end
    
    return temporal_data, time_periods
end

# Visualize specific time period
function visualize_period(temporal_data, period, g, orig_to_graph, graph_to_orig)
    if !haskey(temporal_data, period)
        println("Period $period not found")
        return
    end
    
    data = temporal_data[period]
    graph_nodes = data["nodes"]
    labels = data["labels"]
    clusters = data["clusters"]
    
    # Create subgraph for this period
    subgraph_nodes = Set(graph_nodes)
    period_g = SimpleGraph(length(graph_nodes))
    
    # Map from period graph to original graph
    period_to_orig = Dict{Int, Int}()
    orig_to_period = Dict{Int, Int}()
    
    for (i, orig_graph_idx) in enumerate(graph_nodes)
        period_to_orig[i] = orig_graph_idx
        orig_to_period[orig_graph_idx] = i
    end
    
    # Add edges within the period
    for edge in edges(g)
        src_node, dst_node = src(edge), dst(edge)
        if src_node in subgraph_nodes && dst_node in subgraph_nodes
            add_edge!(period_g, orig_to_period[src_node], orig_to_period[dst_node])
        end
    end
    
    # Create colors based on clusters
    max_cluster = maximum(clusters)
    colors = [HSV(360 * (c-1) / max_cluster, 0.8, 0.9) for c in clusters]
    
    println("Visualizing $period: $(nv(period_g)) nodes, $(ne(period_g)) edges")
    
    # Launch GraphPlayground
    playground(period_g;
        labels=labels,
        link_options=(;distance=30, iterations=1),
        charge_options=(;strength=-200),
        graphplot_options=(;node_color=colors),
        initial_iterations=100)
    
    return period_g, labels, colors
end

# Main analysis function
function analyze_glmakie_evolution()
    println("=== GLMakie Ecosystem Evolution Analysis ===")
    
    # Step 1: Extract temporal dependencies
    temporal_deps, all_deps_ever, glmakie_idx, package_to_index, index_to_package = extract_glmakie_temporal_dependencies()
    
    # Step 2: Create combined graph
    g, labels, orig_to_graph, graph_to_orig, deps_list = create_combined_dependency_graph(
        all_deps_ever, glmakie_idx, package_to_index, index_to_package)
    
    # Step 3: Generate stable layout
    pos_x, pos_y = generate_stable_layout(g, labels)
    
    # Step 4: Run clustering
    cluster_assignment, components = run_louvain_clustering(g)
    
    # Step 5: Create temporal visualization data
    temporal_data, time_periods = create_temporal_visualization_data(
        temporal_deps, all_deps_ever, glmakie_idx, orig_to_graph, graph_to_orig,
        pos_x, pos_y, cluster_assignment, index_to_package)
    
    println("\\n=== Analysis Complete ===")
    println("Time periods: $(length(time_periods))")
    println("Total dependencies ever: $(length(all_deps_ever))")
    println("Clusters found: $(length(components))")
    
    # Return all data for interactive exploration
    return Dict(
        "temporal_deps" => temporal_deps,
        "all_deps_ever" => all_deps_ever,
        "glmakie_idx" => glmakie_idx,
        "combined_graph" => g,
        "labels" => labels,
        "orig_to_graph" => orig_to_graph,
        "graph_to_orig" => graph_to_orig,
        "pos_x" => pos_x,
        "pos_y" => pos_y,
        "cluster_assignment" => cluster_assignment,
        "components" => components,
        "temporal_data" => temporal_data,
        "time_periods" => time_periods,
        "package_to_index" => package_to_index,
        "index_to_package" => index_to_package
    )
end

# Convenience function to visualize a specific period
function show_period(results, period)
    visualize_period(results["temporal_data"], period, results["combined_graph"], 
                    results["orig_to_graph"], results["graph_to_orig"])
end

# Show evolution statistics
function show_evolution_stats(results)
    temporal_data = results["temporal_data"]
    time_periods = results["time_periods"]
    
    println("\\n=== Evolution Statistics ===")
    for period in time_periods
        count = temporal_data[period]["count"]
        println("$period: $count dependencies")
    end
end

# Save results to files
function save_results(results, output_dir="glmakie_evolution_results")
    println("Saving results to $output_dir...")
    
    # Create output directory
    mkpath(output_dir)
    
    # Save temporal dependency counts
    temporal_data = results["temporal_data"]
    time_periods = results["time_periods"]
    
    # Create CSV with evolution statistics
    open("$output_dir/evolution_stats.csv", "w") do f
        println(f, "period,dependency_count")
        for period in time_periods
            count = temporal_data[period]["count"]
            println(f, "$period,$count")
        end
    end
    
    # Save node positions and clusters
    open("$output_dir/node_layout.csv", "w") do f
        println(f, "node_id,package_name,pos_x,pos_y,cluster")
        labels = results["labels"]
        pos_x = results["pos_x"]
        pos_y = results["pos_y"]
        cluster_assignment = results["cluster_assignment"]
        
        for i in 1:length(labels)
            println(f, "$i,$(labels[i]),$(pos_x[i]),$(pos_y[i]),$(cluster_assignment[i])")
        end
    end
    
    # Save temporal data for each period
    mkpath("$output_dir/temporal_data")
    for period in time_periods
        data = temporal_data[period]
        open("$output_dir/temporal_data/nodes_$period.csv", "w") do f
            println(f, "node_id,package_name,pos_x,pos_y,cluster")
            for i in 1:length(data["labels"])
                println(f, "$(data["nodes"][i]),$(data["labels"][i]),$(data["pos_x"][i]),$(data["pos_y"][i]),$(data["clusters"][i])")
            end
        end
    end
    
    # Save edge list of combined graph
    open("$output_dir/combined_graph_edges.csv", "w") do f
        println(f, "source,target,source_name,target_name")
        g = results["combined_graph"]
        labels = results["labels"]
        for edge in edges(g)
            src_idx = src(edge)
            dst_idx = dst(edge)
            println(f, "$src_idx,$dst_idx,$(labels[src_idx]),$(labels[dst_idx])")
        end
    end
    
    # Save cluster information
    open("$output_dir/clusters.csv", "w") do f
        println(f, "cluster_id,package_name,node_id")
        labels = results["labels"]
        cluster_assignment = results["cluster_assignment"]
        
        for i in 1:length(labels)
            println(f, "$(cluster_assignment[i]),$(labels[i]),$i")
        end
    end
    
    # Save summary JSON
    summary = Dict(
        "total_dependencies_ever" => length(results["all_deps_ever"]),
        "total_clusters" => length(results["components"]),
        "time_periods" => length(time_periods),
        "date_range" => "$(time_periods[1]) to $(time_periods[end])",
        "combined_graph_nodes" => nv(results["combined_graph"]),
        "combined_graph_edges" => ne(results["combined_graph"]),
        "glmakie_index" => results["glmakie_idx"]
    )
    
    open("$output_dir/summary.json", "w") do f
        JSON.print(f, summary, 2)
    end
    
    println("Results saved to $output_dir:")
    println("  - evolution_stats.csv: Dependency counts over time")
    println("  - node_layout.csv: Node positions and clusters")
    println("  - temporal_data/: Individual period data files")
    println("  - combined_graph_edges.csv: Graph edge list")
    println("  - clusters.csv: Cluster assignments")
    println("  - summary.json: Analysis summary")
end

# Create animated visualization data for web/external tools
function create_web_visualization_data(results, output_dir="glmakie_evolution_results")
    println("Creating web visualization data...")
    
    mkpath(output_dir)
    
    temporal_data = results["temporal_data"]
    time_periods = results["time_periods"]
    
    # Create JSON data for web visualization
    web_data = Dict(
        "metadata" => Dict(
            "title" => "GLMakie Ecosystem Evolution",
            "date_range" => "$(time_periods[1]) to $(time_periods[end])",
            "total_periods" => length(time_periods),
            "total_dependencies_ever" => length(results["all_deps_ever"])
        ),
        "nodes" => [],
        "links" => [],
        "temporal_frames" => []
    )
    
    # Add all nodes with their static properties
    labels = results["labels"]
    pos_x = results["pos_x"]
    pos_y = results["pos_y"]
    cluster_assignment = results["cluster_assignment"]
    
    for i in 1:length(labels)
        push!(web_data["nodes"], Dict(
            "id" => i,
            "name" => labels[i],
            "x" => pos_x[i],
            "y" => pos_y[i],
            "cluster" => cluster_assignment[i]
        ))
    end
    
    # Add all edges
    g = results["combined_graph"]
    for edge in edges(g)
        push!(web_data["links"], Dict(
            "source" => src(edge),
            "target" => dst(edge)
        ))
    end
    
    # Add temporal frames
    for period in time_periods
        data = temporal_data[period]
        frame = Dict(
            "period" => period,
            "active_nodes" => data["nodes"],
            "node_count" => data["count"]
        )
        push!(web_data["temporal_frames"], frame)
    end
    
    # Save web data
    open("$output_dir/web_visualization_data.json", "w") do f
        JSON.print(f, web_data, 2)
    end
    
    println("Web visualization data saved to $output_dir/web_visualization_data.json")
    
    return web_data
end