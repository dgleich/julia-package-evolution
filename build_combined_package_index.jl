#!/usr/bin/env julia
"""
build_combined_package_index.jl

This script builds a comprehensive package index from both METADATA.jl and
General registry dependency data, preserving temporal ordering.
"""

using JSON
using Dates

function load_json(filepath)
    open(filepath, "r") do f
        return JSON.parse(read(f, String))
    end
end

function save_json(data, filepath)
    open(filepath, "w") do f
        JSON.print(f, data, 2)
    end
end

function get_dependency_files(directory, prefix="")
    # Get all dependency files in the directory
    all_files = readdir(directory)
    
    # Match both standard and metadata dependency files
    general_files = filter(f -> startswith(f, "dependencies_") && endswith(f, ".json"), all_files)
    metadata_files = filter(f -> startswith(f, "metadata_dependencies_") && endswith(f, ".json"), all_files)
    
    # Combine both sets of files
    files = vcat(general_files, metadata_files)
    
    # Extract month from filename
    month_pattern = r"dependencies_(\d{4}-\d{2})\.json$"
    metadata_month_pattern = r"metadata_dependencies_(\d{4}-\d{2})\.json$"
    
    file_dates = Dict()
    for file in files
        if startswith(file, "metadata_")
            m = match(metadata_month_pattern, file)
            if m !== nothing
                month = m.captures[1]
                file_dates[file] = Date(parse(Int, split(month, "-")[1]), 
                                       parse(Int, split(month, "-")[2]), 
                                       1)
            end
        else
            m = match(month_pattern, file)
            if m !== nothing
                month = m.captures[1]
                file_dates[file] = Date(parse(Int, split(month, "-")[1]), 
                                       parse(Int, split(month, "-")[2]), 
                                       1)
            end
        end
    end
    
    # Sort files by date
    sorted_files = sort(collect(keys(file_dates)), by=f -> file_dates[f])
    return sorted_files
end

function build_package_index()
    println("Building combined package index...")

    # Get all dependency files
    dependency_files = get_dependency_files(".")
    println("Found $(length(dependency_files)) dependency files")
    
    # Initialize package index
    package_metadata = Dict()
    
    # Track the current index (will be incremented for each new package)
    current_index = 0
    
    # Process each dependency file in chronological order
    for (i, file) in enumerate(dependency_files)
        println("[$i/$(length(dependency_files))] Processing $file...")
        
        # Extract date from filename
        date_str = if occursin("metadata_dependencies_", file)
            m = match(r"metadata_dependencies_(\d{4}-\d{2})\.json$", file)
            m === nothing ? nothing : m.captures[1]
        else
            m = match(r"dependencies_(\d{4}-\d{2})\.json$", file)
            m === nothing ? nothing : m.captures[1]
        end
        
        if date_str === nothing
            println("  Warning: Could not extract date from filename $file, skipping")
            continue
        end
        
        # Load dependency data
        data = load_json(file)
        source = startswith(file, "metadata_") ? "metadata" : "general"
        
        # Process packages
        for (pkg_name, pkg_info) in data["packages"]
            # Skip if package doesn't have metadata
            if !haskey(pkg_info, "metadata") || pkg_info["metadata"] === nothing
                continue
            end
            
            # Get UUID
            uuid = pkg_info["metadata"]["uuid"]
            
            # If this is a new package, add it to the index
            if !haskey(package_metadata, pkg_name) && 
               !any(metadata -> get(metadata, "uuid", "") == uuid, values(package_metadata))
                current_index += 1
                package_metadata[pkg_name] = Dict(
                    "index" => current_index,
                    "first_seen" => date_str,
                    "source" => source,
                    "uuid" => uuid
                )
            end
        end
    end
    
    # Create final package index structure
    package_index = Dict(
        "package_metadata" => Dict(
            pkg => Dict(
                "index" => info["index"],
                "first_seen" => info["first_seen"],
                "source" => info["source"]
            ) for (pkg, info) in package_metadata
        )
    )
    
    # Save package index
    save_json(package_index, "combined_package_index.json")
    
    println("Package index built with $(length(package_metadata)) packages")
    
    # Count packages by source
    metadata_count = count(info -> info["source"] == "metadata", values(package_metadata))
    general_count = count(info -> info["source"] == "general", values(package_metadata))
    
    println("  METADATA.jl packages: $metadata_count")
    println("  General registry packages: $general_count")
    
    return package_index
end

function main()
    package_index = build_package_index()
end

main()