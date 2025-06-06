#!/usr/bin/env julia

using JSON
using Dates
using SparseArrays

"""
Build sparse adjacency matrices for each month with fixed dependency parsing for
General registry files.

Transition point: February 25, 2018 - commit fdea9f164d45b616ce775e5506c0bbef70f3bb29
"""

# Define transition date
const TRANSITION_DATE = Date(2018, 2, 25)

# Helper function to extract date from filename
function extract_date(filename)
    # Extract YYYY-MM format from filename for both types of files
    if startswith(basename(filename), "metadata_dependencies_")
        date_str = replace(basename(filename), "metadata_dependencies_" => "", ".json" => "")
    else
        date_str = replace(basename(filename), "dependencies_" => "", ".json" => "")
    end
    
    # Parse the date
    try
        return Date("$(date_str)-01")
    catch
        return nothing # Skip files that don't have a proper date format
    end
end

# Determine which file to use for a given month
function select_dependency_file(files_by_month, month)
    month_date = Date(parse(Int, split(month, "-")[1]), parse(Int, split(month, "-")[2]), 1)
    
    if !haskey(files_by_month, month)
        return nothing
    end
    
    available_files = files_by_month[month]
    
    # Before transition date: prefer METADATA.jl
    # After transition date: prefer General registry
    if month_date < TRANSITION_DATE
        # Look for METADATA.jl file first
        for file in available_files
            if startswith(basename(file), "metadata_dependencies_")
                return file
            end
        end
        # Fall back to General if needed
        return available_files[1]
    else
        # Look for General registry file first
        for file in available_files
            if !startswith(basename(file), "metadata_dependencies_")
                return file
            end
        end
        # Fall back to METADATA.jl if needed
        return available_files[1]
    end
end

# Find all dependency files from both sources and organize by month
function get_dependency_files_by_month()
    # Get all JSON files in the current directory
    all_files = readdir(pwd(), join=true)
    
    # Filter for dependency files
    metadata_files = filter(f -> startswith(basename(f), "metadata_dependencies_") && 
                               endswith(f, ".json"), all_files)
    general_files = filter(f -> startswith(basename(f), "dependencies_") && 
                              endswith(f, ".json") && 
                              !startswith(basename(f), "metadata_"), all_files)
    
    # Combine all files
    files = vcat(metadata_files, general_files)
    
    # Group by month
    files_by_month = Dict{String, Vector{String}}()
    
    for file in files
        date = extract_date(file)
        if date === nothing
            continue
        end
        
        month = Dates.format(date, "yyyy-mm")
        
        if !haskey(files_by_month, month)
            files_by_month[month] = String[]
        end
        
        push!(files_by_month[month], file)
    end
    
    return files_by_month
end

# Write a sparse matrix to a file in SMAT format
function writeSMAT(filename, A::SparseMatrixCSC)
    m, n = size(A)
    rows, cols, vals = findnz(A)
    nnz = length(vals)
    
    open(filename, "w") do f
        # Write header: rows cols nnz
        write(f, "$m $n $nnz\n")
        
        # Write each nonzero entry: row col value (0-indexed)
        for i in 1:nnz
            # Convert to 0-indexed for SMAT format
            write(f, "$(rows[i]-1) $(cols[i]-1) $(vals[i])\n")
        end
    end
end

# Build adjacency matrix for a specific month
function build_adjacency_matrix(dependency_file, package_to_index)
    # Load the JSON data with error handling
    data = open(dependency_file, "r") do io
        JSON.parse(io)
    end
    
    # Get total number of packages in our index
    n = length(package_to_index)
    
    # Create empty sparse matrix
    A = spzeros(Int, n, n)
    
    # Determine data source type (METADATA.jl or General)
    is_metadata = startswith(basename(dependency_file), "metadata_dependencies_")
    
    # Create reverse lookup from UUIDs to package names for General registry
    uuid_to_name = Dict{String, String}()
    if !is_metadata
        for (pkg_name, pkg_info) in data["packages"]
            if haskey(pkg_info, "metadata") && pkg_info["metadata"] !== nothing && 
               haskey(pkg_info["metadata"], "uuid")
                uuid = pkg_info["metadata"]["uuid"]
                uuid_to_name[uuid] = pkg_name
            end
        end
    end
    
    # Debug counters
    edge_count = 0
    skipped_dep_count = 0
    skipped_pkg_count = 0
    
    # Populate the matrix with dependencies
    for (pkg, deps) in data["dependencies"]
        # Skip if package not in our index
        if !haskey(package_to_index, pkg)
            skipped_pkg_count += 1
            continue
        end
        
        # Get row index for this package
        i = package_to_index[pkg]
        
        # Handle dependencies differently based on source
        if is_metadata
            # METADATA.jl format has UUID keys but package names as values
            for (_, dep_name) in deps
                # Skip if dependency not in our index
                if !haskey(package_to_index, dep_name)
                    skipped_dep_count += 1
                    continue
                end
                
                # Get column index for this dependency
                j = package_to_index[dep_name]
                
                # Add edge: package i depends on package j
                A[i, j] = 1
                edge_count += 1
            end
        else
            # General registry format 
            # The deps is a Dict where:
            # - keys are UUIDs of the dependencies
            # - values are the names of the dependencies
            for (dep_uuid, dep_name) in deps
                target_pkg = dep_name
                
                # Skip if dependency not in our index
                if !haskey(package_to_index, target_pkg)
                    skipped_dep_count += 1
                    continue
                end
                
                # Get column index for this dependency
                j = package_to_index[target_pkg]
                
                # Add edge: package i depends on package j
                A[i, j] = 1
                edge_count += 1
            end
        end
    end
    
    return A, edge_count, skipped_pkg_count, skipped_dep_count
end

# Create mapping from package names to indices based on the combined index
function create_package_to_index_mapping(index_data)
    package_to_index = Dict{String, Int}()
    
    for (pkg, info) in index_data["package_metadata"]
        # Use the index from the package metadata
        package_to_index[pkg] = info["index"]
    end
    
    return package_to_index
end

# Main function
function main()
    println("Starting fixed adjacency matrix generation...")
    println("Transition date: $(TRANSITION_DATE)")
    
    # Load package index
    index_file = "combined_package_index.json"
    if !isfile(index_file)
        error("Combined package index file not found. Run build_combined_package_index.jl first.")
    end
    
    index_data = open(index_file, "r") do io
        JSON.parse(io)
    end
    
    # Create mapping from package names to indices
    package_to_index = create_package_to_index_mapping(index_data)
    
    println("Loaded combined package index with $(length(package_to_index)) packages")
    
    # Create matrices directory if it doesn't exist
    matrices_dir = "matrices_fixed"
    if !isdir(matrices_dir)
        mkdir(matrices_dir)
    end
    
    # Group dependency files by month
    files_by_month = get_dependency_files_by_month()
    months = sort(collect(keys(files_by_month)))
    println("Found data for $(length(months)) months")
    
    # Stats
    success_count = 0
    skipped_count = 0
    metadata_count = 0
    general_count = 0
    total_edges = 0
    total_skipped_pkgs = 0
    total_skipped_deps = 0
    
    for month in months
        # Select appropriate file based on transition date
        file_path = select_dependency_file(files_by_month, month)
        if file_path === nothing
            println("No suitable file found for month $month, skipping...")
            skipped_count += 1
            continue
        end
        
        # Determine source
        is_metadata = startswith(basename(file_path), "metadata_dependencies_")
        source_str = is_metadata ? "METADATA.jl" : "General"
        
        # Create output file name
        output_file = joinpath(matrices_dir, "adj_$(month).smat")
        
        println("Processing month $month using $(basename(file_path)) [$(source_str)]...")
        
        try
            # Build adjacency matrix
            A, edge_count, skipped_pkgs, skipped_deps = build_adjacency_matrix(file_path, package_to_index)
            
            # Write to SMAT file
            writeSMAT(output_file, A)
            
            # Print stats
            m, n = size(A)
            nnz = length(A.nzval)
            println("  Matrix size: $(m)×$(n) with $(nnz) edges")
            println("  Skipped packages: $skipped_pkgs, Skipped dependencies: $skipped_deps")
            println("  Saved to: $(output_file)")
            success_count += 1
            total_edges += edge_count
            total_skipped_pkgs += skipped_pkgs
            total_skipped_deps += skipped_deps
            
            if is_metadata
                metadata_count += 1
            else
                general_count += 1
            end
        catch e
            println("  Error processing file: $e")
            println("  Skipping month $month")
            skipped_count += 1
        end
    end
    
    println("\nMatrix generation summary:")
    println("  Successfully generated: $success_count")
    println("    - From METADATA.jl: $metadata_count")
    println("    - From General registry: $general_count")
    println("  Skipped due to errors: $skipped_count")
    println("  Total edges across all matrices: $total_edges")
    println("  Total skipped packages: $total_skipped_pkgs")
    println("  Total skipped dependencies: $total_skipped_deps")
    
    println("\nAll adjacency matrices generated successfully.")
end

main()