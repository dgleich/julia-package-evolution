#!/usr/bin/env julia
"""
compute_full_pagerank_temporal.jl

Compute PageRank on each time slice and save FULL PageRank vectors (not just top 5)
so we can track the evolution of any package that was ever in the top 10.
"""

using JSON
using SparseArrays
using Dates
using Printf
using MatrixNetworks
using JLD2

function load_json(filepath)
    open(filepath, "r") do f
        return JSON.parse(read(f, String))
    end
end

function read_smat(filename)
    """Read sparse matrix from SMAT format file"""
    open(filename, "r") do f
        # Read header line
        line = readline(f)
        parts = split(line)
        m = parse(Int, parts[1])
        n = parse(Int, parts[2])
        nnz = parse(Int, parts[3])
        
        # Initialize COO format (0-indexed in file, convert to 1-indexed)
        rows = Int[]
        cols = Int[]
        vals = Float64[]
        
        # Read entries
        for line in eachline(f)
            parts = split(line)
            if length(parts) >= 3
                row = parse(Int, parts[1]) + 1  # Convert to 1-indexed
                col = parse(Int, parts[2]) + 1  # Convert to 1-indexed
                val = parse(Float64, parts[3])
                push!(rows, row)
                push!(cols, col)
                push!(vals, val)
            end
        end
        
        return sparse(rows, cols, vals, m, n)
    end
end

function get_matrix_files()
    """Get all adjacency matrix files"""
    matrix_dir = "matrices_fixed"
    if !isdir(matrix_dir)
        error("matrices_fixed directory not found")
    end
    
    files = readdir(matrix_dir)
    matrix_files = filter(f -> startswith(f, "adj_") && endswith(f, ".smat"), files)
    
    # Extract dates and sort
    file_dates = []
    for file in matrix_files
        m = match(r"adj_(\d{4}-\d{2})\.smat$", file)
        if m !== nothing
            year_month = m.captures[1]
            year, month = parse.(Int, split(year_month, "-"))
            date = Date(year, month, 1)
            push!(file_dates, (date=date, file=joinpath(matrix_dir, file), month_str=year_month))
        end
    end
    
    sort!(file_dates, by=x -> x.date)
    return file_dates
end

function load_package_index()
    """Load the combined package index to map indices to package names"""
    index_file = "combined_package_index.json"
    if !isfile(index_file)
        error("combined_package_index.json not found")
    end
    
    index_data = load_json(index_file)
    
    # Create mapping from index to package name
    idx_to_name = Dict{Int, String}()
    
    # Handle the JSON structure - extract from package_metadata
    if haskey(index_data, "package_metadata")
        package_metadata = index_data["package_metadata"]
        for (name, metadata) in package_metadata
            if haskey(metadata, "index")
                idx = metadata["index"]
                if isa(idx, Number)
                    idx_to_name[Int(idx)] = String(name)
                end
            end
        end
    end
    
    return idx_to_name
end

function compute_pagerank_for_matrix(A, alpha=0.85)
    """Compute PageRank and return full vector"""
    n = size(A, 1)
    
    if n == 0 || nnz(A) == 0
        return zeros(n)
    end
    
    try
        # Compute PageRank using MatrixNetworks - ensure matrix is Float64
        A_float = convert(SparseMatrixCSC{Float64, Int}, A)
        pr_scores = pagerank(A_float, alpha)
        return pr_scores
        
    catch e
        println("Error computing PageRank: $e")
        return zeros(n)
    end
end

function compute_full_pagerank_temporal()
    """Main function to compute PageRank for all time slices and save full vectors"""
    
    # Load package index
    println("Loading package index...")
    idx_to_name = load_package_index()
    
    # Get matrix files
    println("Getting matrix files...")
    file_dates = get_matrix_files()
    println("Found $(length(file_dates)) matrix files")
    
    # Prepare data storage
    pagerank_data = Dict()
    pagerank_data["forward"] = Dict()
    pagerank_data["backward"] = Dict()
    pagerank_data["dates"] = String[]
    pagerank_data["idx_to_name"] = idx_to_name
    
    println("Computing PageRank for each time slice...")
    
    for (i, fd) in enumerate(file_dates)
        date_str = fd.month_str
        println("Processing $date_str ($(i)/$(length(file_dates)))")
        
        try
            # Load adjacency matrix
            A = read_smat(fd.file)
            println("  Matrix size: $(size(A)), nnz: $(nnz(A))")
            
            # Forward PageRank (original graph)
            forward_scores = compute_pagerank_for_matrix(A)
            
            # Backward PageRank (transposed graph)
            # Convert transpose to regular sparse matrix to avoid MatrixNetworks issues
            A_T = sparse(A')
            backward_scores = compute_pagerank_for_matrix(A_T)
            
            # Store results
            pagerank_data["forward"][date_str] = forward_scores
            pagerank_data["backward"][date_str] = backward_scores
            push!(pagerank_data["dates"], date_str)
            
            # Print top 3 for verification
            if !isempty(forward_scores) && maximum(forward_scores) > 0
                top_forward_idx = partialsortperm(forward_scores, 1:min(3, length(forward_scores)), rev=true)
                top_forward_names = [get(idx_to_name, idx, "Unknown_$idx") for idx in top_forward_idx]
                println("  Forward top 3: $top_forward_names")
            end
            
            if !isempty(backward_scores) && maximum(backward_scores) > 0
                top_backward_idx = partialsortperm(backward_scores, 1:min(3, length(backward_scores)), rev=true)
                top_backward_names = [get(idx_to_name, idx, "Unknown_$idx") for idx in top_backward_idx]
                println("  Backward top 3: $top_backward_names")
            end
            
        catch e
            println("  Error processing $date_str: $e")
            # Add empty results
            n = length(idx_to_name)
            pagerank_data["forward"][date_str] = zeros(n)
            pagerank_data["backward"][date_str] = zeros(n)
            push!(pagerank_data["dates"], date_str)
        end
    end
    
    # Save the complete PageRank data
    println("Saving complete PageRank data...")
    @save "pagerank_temporal_full.jld2" pagerank_data
    
    println("Full PageRank data saved to pagerank_temporal_full.jld2")
    println("Use this file to analyze PageRank evolution for any package.")
    
    return pagerank_data
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    compute_full_pagerank_temporal()
end