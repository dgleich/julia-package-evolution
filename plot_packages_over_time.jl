#!/usr/bin/env julia
"""
plot_packages_over_time.jl

Plot the number of Julia packages over time using both METADATA.jl and General registry data.
"""

using JSON
using Dates
using Plots
using Printf

function load_json(filepath)
    open(filepath, "r") do f
        return JSON.parse(read(f, String))
    end
end

function get_dependency_files()
    # Get all dependency files
    all_files = readdir(".")
    
    # Match both standard and metadata dependency files
    general_files = filter(f -> startswith(f, "dependencies_") && endswith(f, ".json"), all_files)
    metadata_files = filter(f -> startswith(f, "metadata_dependencies_") && endswith(f, ".json"), all_files)
    
    return general_files, metadata_files
end

function extract_date_from_filename(filename)
    # Extract YYYY-MM from filename
    if startswith(filename, "metadata_")
        m = match(r"metadata_dependencies_(\d{4}-\d{2})\.json$", filename)
    else
        m = match(r"dependencies_(\d{4}-\d{2})\.json$", filename)
    end
    
    if m !== nothing
        year_month = m.captures[1]
        year, month = parse.(Int, split(year_month, "-"))
        return Date(year, month, 1)
    end
    return nothing
end

function count_packages_in_file(filepath)
    try
        data = load_json(filepath)
        if haskey(data, "packages")
            return length(data["packages"])
        end
    catch e
        println("Error reading $filepath: $e")
    end
    return 0
end

function plot_packages_over_time()
    general_files, metadata_files = get_dependency_files()
    
    # Collect data points
    dates = Date[]
    package_counts = Int[]
    registry_types = String[]
    
    # Process metadata files (METADATA.jl registry)
    for file in metadata_files
        date = extract_date_from_filename(file)
        if date !== nothing
            count = count_packages_in_file(file)
            if count > 0
                push!(dates, date)
                push!(package_counts, count)
                push!(registry_types, "METADATA.jl")
            end
        end
    end
    
    # Process general files (General registry)
    for file in general_files
        date = extract_date_from_filename(file)
        if date !== nothing
            count = count_packages_in_file(file)
            if count > 0
                push!(dates, date)
                push!(package_counts, count)
                push!(registry_types, "General")
            end
        end
    end
    
    # Sort by date
    sort_indices = sortperm(dates)
    dates = dates[sort_indices]
    package_counts = package_counts[sort_indices]
    registry_types = registry_types[sort_indices]
    
    # Handle registry transition properly
    # Use METADATA.jl before Feb 25, 2018 and General registry after
    transition_date = Date(2018, 2, 25)
    
    # Create clean dataset with no overlaps
    clean_dates = Date[]
    clean_counts = Int[]
    clean_types = String[]
    
    # Group by date and pick the appropriate registry
    date_groups = Dict{Date, Vector{Int}}()
    date_registries = Dict{Date, Vector{String}}()
    
    for i in 1:length(dates)
        date = dates[i]
        if !haskey(date_groups, date)
            date_groups[date] = Int[]
            date_registries[date] = String[]
        end
        push!(date_groups[date], package_counts[i])
        push!(date_registries[date], registry_types[i])
    end
    
    # For each date, choose the appropriate registry
    for date in sort(collect(keys(date_groups)))
        registries = date_registries[date]
        counts = date_groups[date]
        
        if date < transition_date
            # Before transition: prefer METADATA.jl
            metadata_idx = findfirst(r -> r == "METADATA.jl", registries)
            if metadata_idx !== nothing
                push!(clean_dates, date)
                push!(clean_counts, counts[metadata_idx])
                push!(clean_types, "METADATA.jl")
            else
                # Fallback to General if no METADATA.jl data
                push!(clean_dates, date)
                push!(clean_counts, counts[1])
                push!(clean_types, "General")
            end
        else
            # After transition: prefer General registry
            general_idx = findfirst(r -> r == "General", registries)
            if general_idx !== nothing
                push!(clean_dates, date)
                push!(clean_counts, counts[general_idx])
                push!(clean_types, "General")
            else
                # Fallback to METADATA.jl if no General data
                push!(clean_dates, date)
                push!(clean_counts, counts[1])
                push!(clean_types, "METADATA.jl")
            end
        end
    end
    
    # Update our arrays with clean data
    dates = clean_dates
    package_counts = clean_counts
    registry_types = clean_types
    
    # Split data by registry for plotting
    metadata_indices = findall(t -> t == "METADATA.jl", registry_types)
    general_indices = findall(t -> t == "General", registry_types)
    
    # Create the plot
    p = plot(
        title="Julia Package Ecosystem Growth Over Time",
        xlabel="Date",
        ylabel="Number of Packages",
        legend=:topleft,
        size=(1000, 600),
        dpi=300
    )
    
    # Plot METADATA.jl era
    if !isempty(metadata_indices)
        plot!(p, dates[metadata_indices], package_counts[metadata_indices],
              label="METADATA.jl Registry", 
              color=:blue, 
              linewidth=2,
              marker=:circle,
              markersize=3)
    end
    
    # Plot General registry era
    if !isempty(general_indices)
        plot!(p, dates[general_indices], package_counts[general_indices],
              label="General Registry", 
              color=:red, 
              linewidth=2,
              marker=:circle,
              markersize=3)
    end
    
    # Add vertical line for transition
    vline!(p, [transition_date], 
           label="Registry Transition", 
           color=:gray, 
           linestyle=:dash, 
           linewidth=2)
    
    # Add annotations
    if !isempty(dates) && !isempty(package_counts)
        # Annotate first and last points
        first_count = package_counts[1]
        last_count = package_counts[end]
        first_date = dates[1]
        last_date = dates[end]
        
        annotate!(p, first_date, first_count + 200, 
                 text(@sprintf("Start: %d packages\n%s", first_count, Dates.format(first_date, "yyyy-mm")), 
                      :left, 10))
        
        annotate!(p, last_date, last_count - 1000, 
                 text(@sprintf("Latest: %d packages\n%s", last_count, Dates.format(last_date, "yyyy-mm")), 
                      :right, 10))
    end
    
    # Print summary statistics
    println("Julia Package Ecosystem Growth Summary:")
    println("=====================================")
    if !isempty(dates)
        println(@sprintf("Time period: %s to %s", 
                Dates.format(first(dates), "yyyy-mm"), 
                Dates.format(last(dates), "yyyy-mm")))
        println(@sprintf("Package count growth: %d → %d packages", 
                first(package_counts), last(package_counts)))
        
        # Growth by era
        if !isempty(metadata_indices)
            metadata_start = package_counts[first(metadata_indices)]
            metadata_end = package_counts[last(metadata_indices)]
            println(@sprintf("METADATA.jl era: %d → %d packages", metadata_start, metadata_end))
        end
        
        if !isempty(general_indices)
            general_start = package_counts[first(general_indices)]
            general_end = package_counts[last(general_indices)]
            println(@sprintf("General registry era: %d → %d packages", general_start, general_end))
        end
    end
    
    # Save the plot
    savefig(p, "packages_over_time.png")
    println("\nPlot saved as 'packages_over_time.png'")
    
    return p
end

# Run the analysis
if abspath(PROGRAM_FILE) == @__FILE__
    plot_packages_over_time()
end