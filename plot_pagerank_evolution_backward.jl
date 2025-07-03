#!/usr/bin/env julia
"""
plot_pagerank_evolution_backward.jl

Compute backward PageRank (transposed graph) on-the-fly for each time slice, 
find all packages that were ever in the top 10, and plot their evolution.
"""

using JSON
using SparseArrays
using Dates
using Printf
using Plots
using MatrixNetworks

include("plot_pagerank_evolution_full.jl")  # Reuse helper functions

function plot_pagerank_evolution_backward()
    """Main function to compute and plot backward PageRank evolution"""
    
    # Load package index
    println("Loading package index...")
    idx_to_name = load_package_index()
    name_to_idx = Dict(name => idx for (idx, name) in idx_to_name)
    
    # Get matrix files
    println("Getting matrix files...")
    file_dates = get_matrix_files()
    println("Found $(length(file_dates)) matrix files")
    
    # First pass: compute all PageRank vectors and find top 10 packages ever
    println("First pass: Finding all packages that were ever in top 10 (backward)...")
    all_top10_packages = Set{String}()
    
    for (i, fd) in enumerate(file_dates)
        if i % 20 == 0 || i == length(file_dates)
            println("  Processing $(fd.month_str) ($(i)/$(length(file_dates)))")
        end
        
        try
            # Load adjacency matrix
            A = read_smat(fd.file)
            
            if nnz(A) > 0
                # Backward PageRank (transposed graph)
                A_T = sparse(A')
                backward_scores = compute_pagerank_for_matrix(A_T)
                
                if !isempty(backward_scores) && maximum(backward_scores) > 0
                    # Get top 10 indices
                    top10_idx = partialsortperm(backward_scores, 1:min(10, length(backward_scores)), rev=true)
                    
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
    println("Found $(length(top10_packages)) packages that were ever in top 10 (backward)")
    println("Top 10 packages: $(top10_packages[1:min(10, end)])")
    
    # Second pass: compute PageRank history for these packages
    println("Second pass: Computing backward PageRank history for top packages...")
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
                # Backward PageRank (transposed graph)
                A_T = sparse(A')
                backward_scores = compute_pagerank_for_matrix(A_T)
                
                # Extract scores for our packages of interest
                for pkg in top10_packages
                    if haskey(name_to_idx, pkg)
                        idx = name_to_idx[pkg]
                        if idx <= length(backward_scores)
                            push!(pagerank_history[pkg], backward_scores[idx])
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
    
    # Define colors for complex packages (those with many dependencies)
    complex_colors = Dict{String, Symbol}()
    
    # Scientific computing packages
    scientific_packages = ["OrdinaryDiffEq", "DifferentialEquations", "GAP", "Mads", "BIGUQ", "InvariantCausalPrediction", "DSGE", "StateSpaceRoutines"]
    for pkg in scientific_packages
        complex_colors[pkg] = :red
    end
    
    # AWS/Cloud packages
    aws_packages = ["AWSLambda", "AWSSNS", "AWSEC2", "AWSIAM", "AWSCore", "AWSS3"]
    for pkg in aws_packages
        complex_colors[pkg] = :blue
    end
    
    # Visualization packages
    viz_packages = ["Gadfly", "GLPlot", "GLVisualize", "Escher", "Winston", "Plots"]
    for pkg in viz_packages
        complex_colors[pkg] = :green
    end
    
    # Development/utility packages
    dev_packages = ["ExpressCommands", "Atom", "Gallium", "ProfileView", "AutomationLabs", "GenieBuiltLifeProto"]
    for pkg in dev_packages
        complex_colors[pkg] = :purple
    end
    
    p = plot(
        title="PageRank Evolution: Packages Ever in Top 10 (Backward - High Dependency Complexity)",
        xlabel="Date",
        ylabel="PageRank Score",
        legend=:outerright,
        size=(1400, 900),
        dpi=300,
        legendfontsize=6,
        guidefontsize=11,
        titlefontsize=14
    )
    
    # Plot each package
    for pkg in top10_packages
        pkg_history = pagerank_history[pkg]
        
        # Only plot if package has non-zero values at some point
        if !isempty(pkg_history) && maximum(pkg_history) > 0
            color = get(complex_colors, pkg, :gray)
            alpha = (color == :gray) ? 0.4 : 0.8
            linewidth = (color in [:red, :blue]) ? 3 : (color in [:green, :purple]) ? 2 : 1
            
            plot!(p, dates, pkg_history, 
                  label=pkg, 
                  color=color, 
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
    max_score = maximum([maximum(pagerank_history[pkg]) for pkg in top10_packages if maximum(pagerank_history[pkg]) > 0])
    
    annotate!(p, Date(2016, 6, 1), max_score * 0.9, 
             text("AWS Era\n(2017-2020)", :center, 9, :blue))
    
    annotate!(p, Date(2022, 6, 1), max_score * 0.7, 
             text("Complex Packages\n(2020-2025)", :center, 9, :red))
    
    println("Saving plot...")
    savefig(p, "pagerank_evolution_backward.png")
    
    # Print summary statistics
    println("\nTop packages by maximum backward PageRank achieved:")
    max_scores = [(pkg, maximum(pagerank_history[pkg])) for pkg in top10_packages if maximum(pagerank_history[pkg]) > 0]
    sort!(max_scores, by=x->x[2], rev=true)
    
    for (i, (pkg, max_score)) in enumerate(max_scores[1:min(15, end)])
        println(@sprintf("%2d. %-25s: %.6f", i, pkg, max_score))
    end
    
    println("\nPlot saved as 'pagerank_evolution_backward.png'")
    
    return p, pagerank_history, dates
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    plot_pagerank_evolution_backward()
end