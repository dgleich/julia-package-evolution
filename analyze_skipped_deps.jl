#!/usr/bin/env julia

using JSON

"""
Analyze which dependencies are being skipped during adjacency matrix generation.
Output a log file with details on skipped dependencies for analysis.
"""

function create_package_to_index_mapping(index_data)
    package_to_index = Dict{String, Int}()
    
    for (pkg, info) in index_data["package_metadata"]
        # Use the index from the package metadata
        package_to_index[pkg] = info["index"]
    end
    
    return package_to_index
end

function analyze_skipped_dependencies(month="2025-05")
    # Load package index
    index_file = "combined_package_index.json"
    if !isfile(index_file)
        error("Combined package index file not found.")
    end
    
    index_data = open(index_file, "r") do io
        JSON.parse(io)
    end
    
    # Create mapping from package names to indices
    package_to_index = create_package_to_index_mapping(index_data)
    
    println("Loaded combined package index with $(length(package_to_index)) packages")
    
    # Load dependency file for the specified month
    dependency_file = "dependencies_$(month).json"
    if !isfile(dependency_file)
        error("Dependency file for month $(month) not found.")
    end
    
    data = open(dependency_file, "r") do io
        JSON.parse(io)
    end
    
    # Open log file
    log_file = "skipped_dependencies_$(month).log"
    open(log_file, "w") do log
        # Write header
        write(log, "# Skipped Dependencies Analysis for $(month)\n\n")
        write(log, "## Summary\n")
        write(log, "- Total packages in index: $(length(package_to_index))\n")
        write(log, "- Total packages in dependency file: $(length(data["dependencies"]))\n\n")
        write(log, "## Packages not found in index\n")
        
        # Track packages not in index
        packages_not_in_index = String[]
        for pkg in keys(data["dependencies"])
            if !haskey(package_to_index, pkg)
                push!(packages_not_in_index, pkg)
            end
        end
        
        if !isempty(packages_not_in_index)
            for pkg in sort(packages_not_in_index)
                write(log, "- $(pkg)\n")
            end
        else
            write(log, "- None\n")
        end
        
        write(log, "\n## Skipped Dependencies\n")
        
        # Track detailed skipped dependencies
        skipped_deps_count = 0
        skipped_deps_by_pkg = Dict{String, Vector{String}}()
        
        # Track unique skipped dependencies
        unique_skipped_deps = Set{String}()
        
        # Analyze skipped dependencies
        for (pkg, deps) in data["dependencies"]
            if !haskey(package_to_index, pkg)
                continue # Skip packages not in our index
            end
            
            skipped_for_pkg = String[]
            
            for (dep_name, dep_uuid) in deps
                if !haskey(package_to_index, dep_name)
                    push!(skipped_for_pkg, dep_name)
                    push!(unique_skipped_deps, dep_name)
                    skipped_deps_count += 1
                end
            end
            
            if !isempty(skipped_for_pkg)
                skipped_deps_by_pkg[pkg] = skipped_for_pkg
            end
        end
        
        write(log, "Total skipped dependencies: $(skipped_deps_count)\n")
        write(log, "Unique skipped dependencies: $(length(unique_skipped_deps))\n\n")
        
        write(log, "### Unique Skipped Dependencies (Alphabetical)\n")
        for dep in sort(collect(unique_skipped_deps))
            write(log, "- $(dep)\n")
        end
        
        write(log, "\n### Packages with Skipped Dependencies\n")
        write(log, "Format: Package: [list of skipped dependencies]\n\n")
        
        for (pkg, deps) in sort(collect(skipped_deps_by_pkg), by=x->x[1])
            write(log, "$(pkg): $(deps)\n")
        end
    end
    
    println("Analysis complete. Skipped dependencies written to $(log_file)")
end

# Run the analysis for the specified month
analyze_skipped_dependencies()