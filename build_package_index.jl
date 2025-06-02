#!/usr/bin/env julia

using JSON
using Dates

"""
Build a comprehensive index mapping for all packages across all monthly snapshots.
The index will preserve temporal ordering of when packages first appeared.
"""

# Helper function to extract date from filename
function extract_date(filename)
    # Extract YYYY-MM format from filename
    date_str = replace(basename(filename), "dependencies_" => "", ".json" => "")
    
    # Parse the date
    try
        return Date("$(date_str)-01")
    catch
        return nothing # Skip files that don't have a proper date format
    end
end

# Find all dependency files
function get_dependency_files()
    files = filter(f -> startswith(basename(f), "dependencies_") && endswith(f, ".json"), readdir(pwd(), join=true))
    
    # Filter out files without proper date format
    dated_files = filter(f -> extract_date(f) !== nothing, files)
    
    # Sort by date
    sort!(dated_files, by=extract_date)
    
    return dated_files
end

# Build package index
function build_package_index()
    files = get_dependency_files()
    
    # Data structures to track packages
    package_first_seen = Dict{String, Date}()
    packages_by_month = Dict{Date, Vector{String}}()
    
    println("Building package index from $(length(files)) monthly snapshots...")
    
    # First pass: collect all packages and track when they first appeared
    for file_path in files
        date = extract_date(file_path)
        if date === nothing
            continue
        end
        
        # Load data
        println("Processing $(basename(file_path))...")
        try
            data = open(file_path, "r") do io
                JSON.parse(io)
            end
            
            # Get all package names for this month
            current_packages = collect(keys(data["packages"]))
            packages_by_month[date] = current_packages
            
            # Update first seen date for each package
            for pkg in current_packages
                if !haskey(package_first_seen, pkg) || date < package_first_seen[pkg]
                    package_first_seen[pkg] = date
                end
            end
        catch e
            println("  Error processing file: $e")
            println("  Skipping $(basename(file_path))")
        end
    end
    
    # Sort packages by first appearance date
    sorted_packages = sort(collect(keys(package_first_seen)), by=pkg -> package_first_seen[pkg])
    
    # Create final index mapping
    package_to_index = Dict{String, Int}()
    index_to_package = Dict{Int, String}()
    package_metadata = Dict{String, Dict{String, Any}}()
    
    for (i, pkg) in enumerate(sorted_packages)
        package_to_index[pkg] = i
        index_to_package[i] = pkg
        
        # Add metadata
        package_metadata[pkg] = Dict{String, Any}(
            "index" => i,
            "first_seen" => string(package_first_seen[pkg])
        )
    end
    
    # Count packages per month
    monthly_counts = Dict{String, Int}()
    for (date, pkgs) in packages_by_month
        monthly_counts[string(date)] = length(pkgs)
    end
    
    # Create result
    result = Dict{String, Any}(
        "package_to_index" => package_to_index,
        "index_to_package" => Dict(string(k) => v for (k, v) in index_to_package),
        "package_metadata" => package_metadata,
        "total_packages" => length(sorted_packages),
        "monthly_counts" => monthly_counts
    )
    
    return result
end

# Main function
function main()
    println("Starting package index generation...")
    
    # Build the package index
    index_data = build_package_index()
    
    # Save the index to a file
    output_file = "package_index.json"
    open(output_file, "w") do io
        JSON.print(io, index_data, 2) # Pretty print with 2-space indent
    end
    
    println("Package index saved to $(output_file)")
    println("Total packages indexed: $(index_data["total_packages"])")
    
    # Print some statistics
    println("\nPackages per month:")
    monthly_counts = index_data["monthly_counts"]
    for date in sort(collect(keys(monthly_counts)))
        println("  $date: $(monthly_counts[date])")
    end
end

main()