#!/usr/bin/env julia
"""
plot_pagerank_evolution.jl

Plot the evolution of PageRank values over time for all packages that were ever 
in the top 10 for any month (forward PageRank).
"""

using CSV
using DataFrames
using Plots
using Dates
using Printf

function load_pagerank_data(filename)
    """Load PageRank CSV data"""
    df = CSV.read(filename, DataFrame)
    return df
end

function extract_top_packages(df, top_n=10)
    """Extract all packages that were ever in the top N for any month"""
    all_top_packages = Set{String}()
    
    # Look through all rank columns
    rank_cols = [col for col in names(df) if occursin("Rank", col) && occursin("Package", col)]
    
    for row in eachrow(df)
        for col in rank_cols
            pkg = row[col]
            if !ismissing(pkg) && pkg != ""
                push!(all_top_packages, pkg)
            end
        end
    end
    
    return sort(collect(all_top_packages))
end

function build_pagerank_history(df, packages)
    """Build PageRank history for all specified packages"""
    
    # Parse dates - handle the string format in the CSV
    dates = Date[]
    for year_month in df.Month
        if year_month != ""
            try
                # Parse format like "2012-08" to Date
                push!(dates, Date(year_month * "-01"))
            catch e
                println("Warning: Could not parse date: $year_month, error: $e")
            end
        end
    end
    
    # Initialize history dictionary
    history = Dict{String, Vector{Float64}}()
    for pkg in packages
        history[pkg] = fill(0.0, length(dates))
    end
    
    # Fill in the actual PageRank values
    rank_package_cols = [col for col in names(df) if occursin("Rank", col) && occursin("Package", col)]
    rank_score_cols = [col for col in names(df) if occursin("Rank", col) && occursin("Score", col)]
    
    date_idx = 1
    for (i, row) in enumerate(eachrow(df))
        # Skip rows with empty month
        if row.Month == ""
            continue
        end
        
        for (pkg_col, score_col) in zip(rank_package_cols, rank_score_cols)
            pkg = row[pkg_col]
            score = row[score_col]
            
            if !ismissing(pkg) && pkg != "" && !ismissing(score)
                if haskey(history, pkg) && date_idx <= length(dates)
                    history[pkg][date_idx] = score
                end
            end
        end
        
        date_idx += 1
    end
    
    return dates, history
end

function get_package_colors_and_styles()
    """Define colors and line styles for major package categories"""
    
    # Core infrastructure packages
    core_packages = ["Dates", "Statistics", "REPL", "Markdown", "TOML", "Artifacts", "JLLWrappers", "Preferences"]
    
    # Compatibility and build packages  
    compat_packages = ["Compat", "BinDeps", "SHA", "DelimitedFiles", "BinaryProvider"]
    
    # Data structures and utilities
    data_packages = ["DataFrames", "StatsBase", "DataStructures", "URIParser", "OrderedCollections"]
    
    # Legacy packages
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

function plot_pagerank_evolution(csv_file, output_file="pagerank_evolution.png")
    """Main function to create the PageRank evolution plot"""
    
    println("Loading data from $csv_file...")
    df = load_pagerank_data(csv_file)
    
    println("Extracting packages that were ever in top 10...")
    top_packages = extract_top_packages(df, 10)
    println("Found $(length(top_packages)) packages that were ever in top 10")
    
    println("Building PageRank history...")
    dates, history = build_pagerank_history(df, top_packages)
    
    println("Getting colors and styles...")
    colors, styles = get_package_colors_and_styles()
    
    println("Creating plot...")
    p = plot(
        title="PageRank Evolution: Packages Ever in Top 10 (Forward)",
        xlabel="Date",
        ylabel="PageRank Score",
        legend=:outerright,
        size=(1400, 800),
        dpi=300,
        legendfontsize=6,
        guidefontsize=10,
        titlefontsize=12
    )
    
    # Plot each package
    for pkg in top_packages
        pkg_history = history[pkg]
        
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
    annotate!(p, Date(2014, 6, 1), 0.06, 
             text("Compat Era\n(2015-2020)", :center, 8, :blue))
    
    annotate!(p, Date(2022, 6, 1), 0.04, 
             text("Modern Infrastructure\n(2020-2025)", :center, 8, :red))
    
    println("Saving plot to $output_file...")
    savefig(p, output_file)
    
    # Print summary statistics
    println("\nTop packages by maximum PageRank achieved:")
    max_scores = [(pkg, maximum(history[pkg])) for pkg in top_packages if !isempty(history[pkg]) && maximum(history[pkg]) > 0]
    sort!(max_scores, by=x->x[2], rev=true)
    
    for (i, (pkg, max_score)) in enumerate(max_scores[1:min(15, end)])
        println(@sprintf("%2d. %-20s: %.6f", i, pkg, max_score))
    end
    
    # Print packages by era dominance
    println("\nEra analysis:")
    
    # Early era (2012-2015)
    early_end = Date(2015, 12, 31)
    early_idx = findlast(d -> d <= early_end, dates)
    if early_idx !== nothing
        early_leaders = []
        for pkg in top_packages
            if !isempty(history[pkg]) && early_idx <= length(history[pkg])
                early_max = maximum(history[pkg][1:early_idx])
                if early_max > 0.001
                    push!(early_leaders, (pkg, early_max))
                end
            end
        end
        sort!(early_leaders, by=x->x[2], rev=true)
        println("Early era leaders (2012-2015):")
        for (pkg, score) in early_leaders[1:min(5, end)]
            println(@sprintf("  %-15s: %.6f", pkg, score))
        end
    end
    
    # Compat era (2016-2019)
    compat_start = Date(2016, 1, 1)
    compat_end = Date(2019, 12, 31)
    compat_start_idx = findfirst(d -> d >= compat_start, dates)
    compat_end_idx = findlast(d -> d <= compat_end, dates)
    if compat_start_idx !== nothing && compat_end_idx !== nothing
        compat_leaders = []
        for pkg in top_packages
            if !isempty(history[pkg]) && compat_end_idx <= length(history[pkg])
                compat_max = maximum(history[pkg][compat_start_idx:compat_end_idx])
                if compat_max > 0.001
                    push!(compat_leaders, (pkg, compat_max))
                end
            end
        end
        sort!(compat_leaders, by=x->x[2], rev=true)
        println("Compat era leaders (2016-2019):")
        for (pkg, score) in compat_leaders[1:min(5, end)]
            println(@sprintf("  %-15s: %.6f", pkg, score))
        end
    end
    
    # Modern era (2020-2025)
    modern_start = Date(2020, 1, 1)
    modern_start_idx = findfirst(d -> d >= modern_start, dates)
    if modern_start_idx !== nothing
        modern_leaders = []
        for pkg in top_packages
            if !isempty(history[pkg]) && modern_start_idx <= length(history[pkg])
                modern_max = maximum(history[pkg][modern_start_idx:end])
                if modern_max > 0.001
                    push!(modern_leaders, (pkg, modern_max))
                end
            end
        end
        sort!(modern_leaders, by=x->x[2], rev=true)
        println("Modern era leaders (2020-2025):")
        for (pkg, score) in modern_leaders[1:min(5, end)]
            println(@sprintf("  %-15s: %.6f", pkg, score))
        end
    end
    
    return p, top_packages, history
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    plot_pagerank_evolution("pagerank_forward_temporal.csv")
end