#!/usr/bin/env julia

using JSON

# Load the dependencies from the JSON file
function load_dependencies(filename)
    open(filename, "r") do io
        return JSON.parse(io)
    end
end

# Find packages that depend on a specific package
function find_dependents(data, package_name)
    dependents = String[]
    
    # Get the UUID for our target package
    target_uuid = ""
    if haskey(data["packages"], package_name) && 
       haskey(data["packages"][package_name], "metadata") &&
       haskey(data["packages"][package_name]["metadata"], "uuid")
        target_uuid = data["packages"][package_name]["metadata"]["uuid"]
    end
    
    # Loop through all packages and their dependencies
    for (pkg, deps) in data["dependencies"]
        # Skip if we're looking at the package itself
        if pkg == package_name
            continue
        end
        
        # Check if this package depends on our target package
        for (dep_key, dep_uuid) in deps
            # The key is the dependency name, the value is the UUID
            if dep_key == package_name || (target_uuid != "" && dep_uuid == target_uuid)
                push!(dependents, pkg)
                break
            end
        end
    end
    return dependents
end

# Print dependency information for a package
function print_dependency_info(data, package_name)
    println("\n=== $package_name ===")
    
    # Find packages that depend on this package
    dependents = find_dependents(data, package_name)
    println("\nPackages that depend on $package_name:")
    if isempty(dependents)
        println("  None")
    else
        for dep in sort(dependents)
            println("  $dep")
        end
    end
    
    # Find packages that this package depends on
    println("\n$package_name depends on:")
    if !haskey(data["dependencies"], package_name)
        println("  Package not found in dependency data")
    else
        dependencies = data["dependencies"][package_name]
        if isempty(dependencies)
            println("  None")
        else
            for (dep_name, dep_uuid) in dependencies
                # Find the actual package name from packages data if possible
                pkg_name = dep_name
                # Look up the package info for the UUID if possible
                for (name, pkg_info) in data["packages"]
                    if haskey(pkg_info, "metadata") && 
                       haskey(pkg_info["metadata"], "uuid") && 
                       pkg_info["metadata"]["uuid"] == dep_uuid
                        pkg_name = name
                        break
                    end
                end
                println("  $pkg_name ($dep_uuid)")
            end
        end
    end
    
    # Show package metadata if available
    if haskey(data["packages"], package_name)
        pkg_info = data["packages"][package_name]
        println("\nPackage Information:")
        if haskey(pkg_info, "metadata") && haskey(pkg_info["metadata"], "repo")
            println("  Repository: $(pkg_info["metadata"]["repo"])")
        end
        if haskey(pkg_info, "versions")
            versions = collect(keys(pkg_info["versions"]))
            println("  Versions: $(join(sort(versions), ", "))")
        end
    end
end

# Main function
function main()
    deps_file = "dependencies_6b69cc89.json"
    println("Loading dependencies from $deps_file...")
    data = load_dependencies(deps_file)
    
    # Analyze specific packages - use correct names without .jl extension
    target_packages = ["GenericArpack", "MatrixNetworks", "GraphPlayground"]
    
    for package in target_packages
        print_dependency_info(data, package)
    end
end

main()