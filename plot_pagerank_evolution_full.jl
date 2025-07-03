#!/usr/bin/env julia
"""
plot_pagerank_evolution_full.jl

Compute PageRank on-the-fly for each time slice, find all packages that were ever 
in the top 10, and plot their PageRank evolution over time.
"""

using JSON
using SparseArrays
using Dates
using Printf
using Plots
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

function get_package_colors_and_styles()
    """Define colors and line styles for major package categories"""
    
    # Core infrastructure packages
    core_packages = ["Dates", "Statistics", "REPL", "Markdown", "TOML", "Artifacts", "JLLWrappers", "Preferences"]
    
    # Compatibility and build packages  
    compat_packages = ["Compat", "BinDeps", "SHA", "DelimitedFiles", "BinaryProvider"]
    
    # Data structures and utilities
    data_packages = ["DataFrames", "StatsBase", "DataStructures", "URIParser", "OrderedCollections"]
    
    # Legacy packages - will be styled differently
    legacy_packages = ["Options", "Color", "Cairo", "UTF16", "TextWrap", "GetC", "Stats", "ArrayViews", "Docile", "NumericExtensions", "Distributions", "Lazy", "MacroTools", "StaticArrays"]
    
    colors = Dict{String, Symbol}()
    styles = Dict{String, Symbol}()
    
    # Assign colors
    for pkg in core_packages
        colors[pkg] = :red
        styles[pkg] = :solid
    end
    
    for pkg in compat_packages
        colors[pkg] = :blue
        styles[pkg] = :solid
    end
    
    for pkg in data_packages
        colors[pkg] = :green
        styles[pkg] = :solid
    end
    
    for pkg in legacy_packages
        colors[pkg] = :gray
        styles[pkg] = :dash
    end
    
    return colors, styles
end

function plot_pagerank_evolution_forward()
    """Main function to compute and plot PageRank evolution for forward PageRank"""
    
    # Load package index
    println("Loading package index...")
    idx_to_name = load_package_index()
    name_to_idx = Dict(name => idx for (idx, name) in idx_to_name)
    
    # Get matrix files
    println("Getting matrix files...")
    file_dates = get_matrix_files()
    println("Found $(length(file_dates)) matrix files")
    
    # First pass: compute all PageRank vectors and find top 10 packages ever
    println("First pass: Finding all packages that were ever in top 10...")
    all_top10_packages = Set{String}()
    
    for (i, fd) in enumerate(file_dates)
        if i % 20 == 0 || i == length(file_dates)
            println("  Processing $(fd.month_str) ($(i)/$(length(file_dates)))")
        end
        
        try
            # Load adjacency matrix
            A = read_smat(fd.file)
            
            if nnz(A) > 0
                # Forward PageRank (original graph)
                forward_scores = compute_pagerank_for_matrix(A)
                
                if !isempty(forward_scores) && maximum(forward_scores) > 0
                    # Get top 10 indices
                    top10_idx = partialsortperm(forward_scores, 1:min(10, length(forward_scores)), rev=true)
                    
                    # Add package names to set
                    for idx in top10_idx
                        if haskey(idx_to_name, idx)
                            push!(all_top10_packages, idx_to_name[idx])
                        end
                    end
                end
            end
            
        catch e
            println("  Error processing $(fd.month_str): $e")
        end
    end
    
    top10_packages = sort(collect(all_top10_packages))
    println("Found $(length(top10_packages)) packages that were ever in top 10")
    println("Top 10 packages: $(top10_packages[1:min(10, end)])")
    
    # Second pass: compute PageRank history for these packages
    println("Second pass: Computing PageRank history for top packages...")
    dates = Date[]
    pagerank_history = Dict{String, Vector{Float64}}()
    
    # Initialize history
    for pkg in top10_packages
        pagerank_history[pkg] = Float64[]
    end
    
    for (i, fd) in enumerate(file_dates)
        if i % 20 == 0 || i == length(file_dates)
            println("  Processing $(fd.month_str) ($(i)/$(length(file_dates)))")
        end
        
        push!(dates, fd.date)
        
        try
            # Load adjacency matrix
            A = read_smat(fd.file)
            
            if nnz(A) > 0
                # Forward PageRank
                forward_scores = compute_pagerank_for_matrix(A)
                
                # Extract scores for our packages of interest
                for pkg in top10_packages
                    if haskey(name_to_idx, pkg)
                        idx = name_to_idx[pkg]
                        if idx <= length(forward_scores)
                            push!(pagerank_history[pkg], forward_scores[idx])
                        else
                            push!(pagerank_history[pkg], 0.0)
                        end
                    else
                        push!(pagerank_history[pkg], 0.0)
                    end
                end
            else
                # Empty matrix - all scores are 0
                for pkg in top10_packages
                    push!(pagerank_history[pkg], 0.0)
                end
            end
            
        catch e
            println("  Error processing $(fd.month_str): $e")
            # Add zeros for this time period
            for pkg in top10_packages
                push!(pagerank_history[pkg], 0.0)
            end
        end
    end
    
    # Create the plot
    println("Creating plot...")
    colors, styles = get_package_colors_and_styles()
    
    p = plot(
        title="PageRank Evolution: Packages Ever in Top 10 (Forward)",
        xlabel="Date",
        ylabel="PageRank Score",
        legend=:outerright,
        size=(1400, 900),
        dpi=300,
        legendfontsize=7,
        guidefontsize=11,
        titlefontsize=14
    )
    
    # Plot each package
    for pkg in top10_packages
        pkg_history = pagerank_history[pkg]
        
        # Only plot if package has non-zero values at some point
        if !isempty(pkg_history) && maximum(pkg_history) > 0
            color = get(colors, pkg, :black)
            style = get(styles, pkg, :solid)
            alpha = (color == :gray) ? 0.4 : 0.8  # Make legacy packages more transparent
            linewidth = (color == :red) ? 3 : (color == :blue || color == :green) ? 2 : 1
            
            plot!(p, dates, pkg_history, 
                  label=pkg, 
                  color=color, 
                  linestyle=style,
                  alpha=alpha,
                  linewidth=linewidth)
        end
    end
    
    # Add vertical line for registry transition
    transition_date = Date(2018, 2, 25)
    vline!(p, [transition_date], 
           label="Registry Transition", 
           color=:black, 
           linestyle=:dashdot, 
           linewidth=2,
           alpha=0.7)
    
    # Add annotations for key periods
    annotate!(p, Date(2014, 6, 1), maximum([maximum(pagerank_history[pkg]) for pkg in top10_packages if maximum(pagerank_history[pkg]) > 0]) * 0.9, 
             text("Compat Era\n(2015-2020)", :center, 9, :blue))
    
    annotate!(p, Date(2022, 6, 1), maximum([maximum(pagerank_history[pkg]) for pkg in top10_packages if maximum(pagerank_history[pkg]) > 0]) * 0.7, 
             text("Modern Infrastructure\n(2020-2025)", :center, 9, :red))
    
    println("Saving plot...")
    savefig(p, "pagerank_evolution_forward.png")
    
    # Print summary statistics
    println("\nTop packages by maximum PageRank achieved:")
    max_scores = [(pkg, maximum(pagerank_history[pkg])) for pkg in top10_packages if maximum(pagerank_history[pkg]) > 0]
    sort!(max_scores, by=x->x[2], rev=true)
    
    for (i, (pkg, max_score)) in enumerate(max_scores[1:min(15, end)])
        println(@sprintf("%2d. %-20s: %.6f", i, pkg, max_score))
    end
    
    println("\nPlot saved as 'pagerank_evolution_forward.png'")
    
    return p, pagerank_history, dates
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    plot_pagerank_evolution_forward()
end