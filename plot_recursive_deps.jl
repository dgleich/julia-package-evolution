#!/usr/bin/env julia

using JSON
using Dates
using SparseArrays
using Plots

"""
Track and plot the recursive dependencies of Plots.jl and GLMakie.jl over time.
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

function extract_date_from_filename(filename)
    # Extract YYYY-MM from filename
    match_result = match(r"adj_(\d{4}-\d{2})\.smat", basename(filename))
    if match_result !== nothing
        date_str = match_result[1]
        return Date(date_str * "-01")
    else
        return nothing
    end
end

# Create an adjacency list representation for efficient traversal
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

# Compute the recursive dependencies of a package using adjacency list
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
    for dep in adj_list[package_idx]
        push!(deps, dep)
        push!(queue, dep)
    end
    
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
    
    return deps
end

function main()
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
    
    println("Loaded combined package index with $(length(package_to_index)) packages")
    
    # Check if Plots.jl and GLMakie.jl are in the index
    if !haskey(package_to_index, "Plots")
        error("Plots.jl not found in package index")
    end
    
    if !haskey(package_to_index, "GLMakie")
        error("GLMakie.jl not found in package index")
    end
    
    plots_idx = package_to_index["Plots"]
    glmakie_idx = package_to_index["GLMakie"]
    
    println("Plots.jl index: $(plots_idx)")
    println("GLMakie.jl index: $(glmakie_idx)")
    
    # Get all matrix files
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    
    # Sort by date
    date_matrix_pairs = [(extract_date_from_filename(f), f) for f in matrix_files]
    filter!(pair -> pair[1] !== nothing, date_matrix_pairs)
    sort!(date_matrix_pairs, by=first)
    
    # Track dependencies over time
    dates = Date[]
    plots_recursive_deps = Int[]
    glmakie_recursive_deps = Int[]
    
    for (date, matrix_file) in date_matrix_pairs
        println("Processing $(basename(matrix_file))...")
        
        A = read_smat(matrix_file)
        
        # Create efficient adjacency list representation
        adj_list = create_adjacency_list(A)
        
        # Check if the packages exist in this snapshot
        plots_deps_count = 0
        glmakie_deps_count = 0
        
        # Only compute recursive dependencies if the packages exist in this snapshot
        if plots_idx <= length(adj_list)
            # Compute recursive dependencies for Plots.jl
            plots_deps = compute_recursive_dependencies(adj_list, plots_idx)
            plots_deps_count = length(plots_deps)
            
            # Print a few of the recursive dependencies
            if !isempty(plots_deps)
                sample_deps = collect(plots_deps)[1:min(5, length(plots_deps))]
                dep_names = [get(index_to_package, idx, "Unknown") for idx in sample_deps]
                println("  Sample Plots.jl recursive deps: $(join(dep_names, ", "))")
            end
        else
            println("  Plots.jl does not exist in this snapshot")
        end
        
        if glmakie_idx <= length(adj_list)
            # Compute recursive dependencies for GLMakie.jl
            glmakie_deps = compute_recursive_dependencies(adj_list, glmakie_idx)
            glmakie_deps_count = length(glmakie_deps)
            
            # Print a few of the recursive dependencies
            if !isempty(glmakie_deps)
                sample_deps = collect(glmakie_deps)[1:min(5, length(glmakie_deps))]
                dep_names = [get(index_to_package, idx, "Unknown") for idx in sample_deps]
                println("  Sample GLMakie.jl recursive deps: $(join(dep_names, ", "))")
            end
        else
            println("  GLMakie.jl does not exist in this snapshot")
        end
        
        push!(dates, date)
        push!(plots_recursive_deps, plots_deps_count)
        push!(glmakie_recursive_deps, glmakie_deps_count)
    end
    
    # Create plot
    plt = plot(dates, plots_recursive_deps, 
        label="Plots.jl", 
        linewidth=2, 
        marker=:circle, 
        markersize=3,
        xlabel="Date", 
        ylabel="Number of Recursive Dependencies",
        title="Recursive Dependencies for Visualization Packages Over Time")
    
    plot!(plt, dates, glmakie_recursive_deps, 
        label="GLMakie.jl", 
        linewidth=2, 
        marker=:square, 
        markersize=3)
    
    # Save the plot
    savefig(plt, "recursive_visualization_dependencies.png")
    println("Plot saved to recursive_visualization_dependencies.png")
    
    # Save data as CSV
    open("recursive_visualization_dependencies.csv", "w") do f
        println(f, "Date,Plots.jl,GLMakie.jl")
        for i in 1:length(dates)
            println(f, "$(dates[i]),$(plots_recursive_deps[i]),$(glmakie_recursive_deps[i])")
        end
    end
    println("Data saved to recursive_visualization_dependencies.csv")
end

main()