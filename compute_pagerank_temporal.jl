#!/usr/bin/env julia
"""
compute_pagerank_temporal.jl

Compute PageRank on each time slice for both original (forward) and transposed (backward) graphs.
Output results to CSV files showing top 5 packages by PageRank for each month.
"""

using JSON
using SparseArrays
using Dates
using Printf
using CSV
using DataFrames
using MatrixNetworks

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
            push!(file_dates, (date=date, file=joinpath(matrix_dir, file)))
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

function compute_pagerank_for_matrix(A, idx_to_name, alpha=0.85)
    """Compute PageRank and return top 5 packages with their scores"""
    n = size(A, 1)
    
    if n == 0 || nnz(A) == 0
        return fill("", 5), fill(0.0, 5)
    end
    
    try
        # Compute PageRank using MatrixNetworks - ensure matrix is Float64
        A_float = convert(SparseMatrixCSC{Float64, Int}, A)
        pr_scores = pagerank(A_float, alpha)
        
        # Get top 5 indices
        top_indices = partialsortperm(pr_scores, 1:min(5, length(pr_scores)), rev=true)
        
        # Get package names and scores
        top_names = String[]
        top_scores = Float64[]
        
        for idx in top_indices
            if haskey(idx_to_name, idx)
                push!(top_names, idx_to_name[idx])
                push!(top_scores, pr_scores[idx])
            else
                push!(top_names, "Unknown_$idx")
                push!(top_scores, pr_scores[idx])
            end
        end
        
        # Pad with empty entries if less than 5
        while length(top_names) < 5
            push!(top_names, "")
            push!(top_scores, 0.0)
        end
        
        return top_names, top_scores
        
    catch e
        println("Error computing PageRank: $e")
        return fill("", 5), fill(0.0, 5)
    end
end

function compute_temporal_pagerank()
    """Main function to compute PageRank for all time slices"""
    
    # Load package index
    println("Loading package index...")
    idx_to_name = load_package_index()
    
    # Get matrix files
    println("Getting matrix files...")
    file_dates = get_matrix_files()
    println("Found $(length(file_dates)) matrix files")
    
    # Prepare data for CSV output
    forward_data = []
    backward_data = []
    
    println("Computing PageRank for each time slice...")
    
    for (i, fd) in enumerate(file_dates)
        date_str = Dates.format(fd.date, "yyyy-mm")
        println("Processing $date_str ($(i)/$(length(file_dates)))")
        
        try
            # Load adjacency matrix
            A = read_smat(fd.file)
            println("  Matrix size: $(size(A)), nnz: $(nnz(A))")
            
            # Forward PageRank (original graph)
            forward_names, forward_scores = compute_pagerank_for_matrix(A, idx_to_name)
            
            # Backward PageRank (transposed graph)
            # Convert transpose to regular sparse matrix to avoid MatrixNetworks issues
            A_T = sparse(A')
            backward_names, backward_scores = compute_pagerank_for_matrix(A_T, idx_to_name)
            
            # Store results
            forward_row = [date_str, forward_names..., forward_scores...]
            backward_row = [date_str, backward_names..., backward_scores...]
            
            push!(forward_data, forward_row)
            push!(backward_data, backward_row)
            
            println("  Forward top 3: $(forward_names[1:3])")
            println("  Backward top 3: $(backward_names[1:3])")
            
        catch e
            println("  Error processing $date_str: $e")
            # Add empty row
            empty_row = [date_str, fill("", 5)..., fill(0.0, 5)...]
            push!(forward_data, empty_row)
            push!(backward_data, empty_row)
        end
    end
    
    # Create DataFrames manually to avoid issues
    column_names = ["Month", "Rank1_Package", "Rank2_Package", "Rank3_Package", "Rank4_Package", "Rank5_Package",
                   "Rank1_Score", "Rank2_Score", "Rank3_Score", "Rank4_Score", "Rank5_Score"]
    
    forward_df = DataFrame()
    backward_df = DataFrame()
    
    for (i, col) in enumerate(column_names)
        forward_df[!, col] = [row[i] for row in forward_data]
        backward_df[!, col] = [row[i] for row in backward_data]
    end
    
    # Save to CSV
    println("Saving results...")
    CSV.write("pagerank_forward_temporal.csv", forward_df)
    CSV.write("pagerank_backward_temporal.csv", backward_df)
    
    println("Results saved to:")
    println("  pagerank_forward_temporal.csv")
    println("  pagerank_backward_temporal.csv")
    
    # Print summary of most frequent top packages
    println("\nMost frequent top-ranked packages (Forward):")
    top1_forward = [row[2] for row in forward_data if length(row) >= 2 && row[2] != ""]
    if !isempty(top1_forward)
        counts_forward = sort(collect(countmap(top1_forward)), by=x->x[2], rev=true)
        for (pkg, count) in counts_forward[1:min(10, length(counts_forward))]
            println("  $pkg: $count times")
        end
    end
    
    println("\nMost frequent top-ranked packages (Backward):")
    top1_backward = [row[2] for row in backward_data if length(row) >= 2 && row[2] != ""]
    if !isempty(top1_backward)
        counts_backward = sort(collect(countmap(top1_backward)), by=x->x[2], rev=true)
        for (pkg, count) in counts_backward[1:min(10, length(counts_backward))]
            println("  $pkg: $count times")
        end
    end
    
    return forward_df, backward_df
end

function countmap(arr)
    """Simple countmap implementation"""
    counts = Dict{String, Int}()
    for item in arr
        counts[item] = get(counts, item, 0) + 1
    end
    return counts
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    compute_temporal_pagerank()
end