#!/usr/bin/env julia

using JSON
using Dates
using SparseArrays
using Plots

"""
Track and plot the number of packages with more than 100 recursive dependencies over time.
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
    
    # Get all matrix files
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    
    # Sort by date
    date_matrix_pairs = [(extract_date_from_filename(f), f) for f in matrix_files]
    filter!(pair -> pair[1] !== nothing, date_matrix_pairs)
    sort!(date_matrix_pairs, by=first)
    
    # Track packages with high recursive dependencies over time
    dates = Date[]
    high_recursive_counts = Int[]
    
    for (date, matrix_file) in date_matrix_pairs
        println("Processing $(basename(matrix_file))...")
        
        A = read_smat(matrix_file)
        
        # Create efficient adjacency list representation
        adj_list = create_adjacency_list(A)
        
        # Count packages with more than 100 recursive dependencies
        high_count = 0
        total_packages = length(adj_list)
        
        for package_idx in 1:total_packages
            # Only check packages that exist in this snapshot
            if package_idx <= length(adj_list)
                # Compute recursive dependencies for this package
                recursive_deps = compute_recursive_dependencies(adj_list, package_idx)
                
                if length(recursive_deps) > 100
                    high_count += 1
                end
            end
        end
        
        println("  Packages with >100 recursive dependencies: $high_count")
        
        push!(dates, date)
        push!(high_recursive_counts, high_count)
    end
    
    # Create plot
    plt = plot(dates, high_recursive_counts, 
        label="Packages with >100 recursive deps", 
        linewidth=2, 
        marker=:circle, 
        markersize=3,
        xlabel="Date", 
        ylabel="Number of Packages",
        title="Packages with High Recursive Dependencies Over Time")
    
    # Save the plot
    savefig(plt, "high_recursive_dependencies.png")
    println("Plot saved to high_recursive_dependencies.png")
    
    # Save data as CSV
    open("high_recursive_dependencies.csv", "w") do f
        println(f, "Date,PackagesWithHighRecursiveDeps")
        for i in 1:length(dates)
            println(f, "$(dates[i]),$(high_recursive_counts[i])")
        end
    end
    println("Data saved to high_recursive_dependencies.csv")
end

main()