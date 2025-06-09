#!/usr/bin/env julia

using JSON
using Dates
using SparseArrays
using Plots

"""
Track and plot the dependencies on Plots.jl and Makie.jl over time.
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
    
    # Check if Plots.jl and Makie.jl are in the index
    if !haskey(package_to_index, "Plots")
        error("Plots.jl not found in package index")
    end
    
    if !haskey(package_to_index, "Makie")
        error("Makie.jl not found in package index")
    end
    
    plots_idx = package_to_index["Plots"]
    makie_idx = package_to_index["Makie"]
    
    println("Plots.jl index: $(plots_idx)")
    println("Makie.jl index: $(makie_idx)")
    
    # Get all matrix files
    matrix_dir = "matrices_fixed"
    matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
    
    # Sort by date
    date_matrix_pairs = [(extract_date_from_filename(f), f) for f in matrix_files]
    filter!(pair -> pair[1] !== nothing, date_matrix_pairs)
    sort!(date_matrix_pairs, by=first)
    
    # Track dependencies over time
    dates = Date[]
    plots_deps = Int[]
    makie_deps = Int[]
    
    for (date, matrix_file) in date_matrix_pairs
        println("Processing $(basename(matrix_file))...")
        
        A = read_smat(matrix_file)
        
        # Count dependencies on Plots.jl (packages that depend on Plots)
        # This is the column sum of the Plots.jl column (incoming edges)
        plots_dep_count = 0
        for i in 1:size(A, 1)
            if A[i, plots_idx] != 0
                plots_dep_count += 1
            end
        end
        
        # Count dependencies on Makie.jl (packages that depend on Makie)
        # This is the column sum of the Makie.jl column (incoming edges)
        makie_dep_count = 0
        for i in 1:size(A, 1)
            if A[i, makie_idx] != 0
                makie_dep_count += 1
            end
        end
        
        push!(dates, date)
        push!(plots_deps, plots_dep_count)
        push!(makie_deps, makie_dep_count)
    end
    
    # Create plot
    plt = plot(dates, plots_deps, 
        label="Plots.jl", 
        linewidth=2, 
        marker=:circle, 
        markersize=3,
        xlabel="Date", 
        ylabel="Number of Dependent Packages",
        title="Dependencies on Visualization Packages Over Time")
    
    plot!(plt, dates, makie_deps, 
        label="Makie.jl", 
        linewidth=2, 
        marker=:square, 
        markersize=3)
    
    # Save the plot
    savefig(plt, "visualization_dependencies.png")
    println("Plot saved to visualization_dependencies.png")
    
    # Save data as CSV
    open("visualization_dependencies.csv", "w") do f
        println(f, "Date,Plots.jl,Makie.jl")
        for i in 1:length(dates)
            println(f, "$(dates[i]),$(plots_deps[i]),$(makie_deps[i])")
        end
    end
    println("Data saved to visualization_dependencies.csv")
end

main()