#!/usr/bin/env julia

using JSON
using Dates
using SparseArrays

"""
Build sparse adjacency matrices for each month using the combined package index
that incorporates both METADATA.jl and General registry data.
"""

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

# Find all dependency files from both sources
function get_dependency_files()
    # Get all JSON files in the current directory
    all_files = readdir(pwd(), join=true)
    
    # Filter for dependency files
    metadata_files = filter(f -> startswith(basename(f), "metadata_dependencies_") && endswith(f, ".json"), all_files)
    general_files = filter(f -> startswith(basename(f), "dependencies_") && endswith(f, ".json"), all_files)
    
    # Combine all files
    files = vcat(metadata_files, general_files)
    
    # Filter out files without proper date format
    dated_files = filter(f -> extract_date(f) !== nothing, files)
    
    # Sort by date
    sort!(dated_files, by=extract_date)
    
    return dated_files
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
    
    # Populate the matrix with dependencies
    for (pkg, deps) in data["dependencies"]
        # Skip if package not in our index
        if !haskey(package_to_index, pkg)
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
                    continue
                end
                
                # Get column index for this dependency
                j = package_to_index[dep_name]
                
                # Add edge: package i depends on package j
                A[i, j] = 1
            end
        else
            # General registry format
            for (_, dep_name) in deps
                # Skip if dependency not in our index
                if !haskey(package_to_index, dep_name)
                    continue
                end
                
                # Get column index for this dependency
                j = package_to_index[dep_name]
                
                # Add edge: package i depends on package j
                A[i, j] = 1
            end
        end
    end
    
    return A
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
    println("Starting combined adjacency matrix generation...")
    
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
    matrices_dir = "matrices"
    if !isdir(matrices_dir)
        mkdir(matrices_dir)
    end
    
    # Process each dependency file
    dependency_files = get_dependency_files()
    println("Found $(length(dependency_files)) dependency files to process")
    
    success_count = 0
    skipped_count = 0
    metadata_count = 0
    general_count = 0
    
    for file_path in dependency_files
        date = extract_date(file_path)
        if date === nothing
            continue
        end
        
        date_str = Dates.format(date, "yyyy-mm")
        output_file = joinpath(matrices_dir, "adj_$(date_str).smat")
        
        # Determine source
        is_metadata = startswith(basename(file_path), "metadata_dependencies_")
        source_str = is_metadata ? "METADATA.jl" : "General"
        
        println("Processing $(basename(file_path)) [$(source_str)]...")
        
        try
            # Build adjacency matrix
            A = build_adjacency_matrix(file_path, package_to_index)
            
            # Write to SMAT file
            writeSMAT(output_file, A)
            
            # Print stats
            m, n = size(A)
            nnz = length(A.nzval)
            println("  Matrix size: $(m)×$(n) with $(nnz) edges")
            println("  Saved to: $(output_file)")
            success_count += 1
            
            if is_metadata
                metadata_count += 1
            else
                general_count += 1
            end
        catch e
            println("  Error processing file: $e")
            println("  Skipping $(basename(file_path))")
            skipped_count += 1
        end
    end
    
    println("\nMatrix generation summary:")
    println("  Successfully generated: $success_count")
    println("    - From METADATA.jl: $metadata_count")
    println("    - From General registry: $general_count")
    println("  Skipped due to errors: $skipped_count")
    
    println("\nAll adjacency matrices generated successfully.")
end

main()