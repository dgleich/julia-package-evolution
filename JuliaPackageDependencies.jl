""" 
This is a module to work with Julia package dependencies over time. 
It is setup to handle details of how dependencies have been encoded in the
original METADATA.jl repo as well as the move to the new General repo around 2018. 

Repo links:
- https://github.com/JuliaLang/METADATA.jl
- https://github.com/JuliaRegistries/General

Key features:

        import JuliaPackageDependencies 
        const JPD = JuliaPackageDependencies
        
        D = JPD.dependencies(commit_hash) # returns Dependencies for specific commit
        D, d = JPD.next_commit!(D) # returns the new dependencies D and the delta structure, d
        
        
        
"""
module JuliaPackageDependencies

using Graphs
using Dates
using JSON
using TOML
using Pkg

# Type definitions
struct Dependencies
    g::SimpleDiGraph
    c::String  # commit hash
    dt::DateTime  # timestamp
    active_repo::Symbol  # :METADATA or :GENERAL
    packages::Dict{String,Int}  # package name -> node id mapping
end

function Base.show(io::IO, d::Dependencies)
    n_packages = length(d.packages)
    n_edges = ne(d.g)
    repo = d.active_repo == :METADATA ? "METADATA" : "General"
    println(io, "Dependencies($(n_packages) packages, $(n_edges) edges, $(repo) @ $(d.c[1:7]))")
end

struct DependenciesDelta
    new_packages::Vector{String}
    removed_packages::Vector{String}
    new_edges::Vector{Tuple{Int,Int}}
    removed_edges::Vector{Tuple{Int,Int}}
    dt::DateTime
    commit::String
    active_repo::Symbol
end

function Base.show(io::IO, d::DependenciesDelta)
    repo = d.active_repo == :METADATA ? "METADATA" : "General"
    println(io, "DependenciesDelta(+$(length(d.new_packages)) pkgs, -$(length(d.removed_packages)) pkgs, +$(length(d.new_edges)) edges, -$(length(d.removed_edges)) edges, $(repo) @ $(d.commit[1:7]))")
end

@enum Repository METADATA GENERAL

struct RepositoryState
    commit::String
    dt::DateTime
    active_repo::Repository
    metadata_commits::Vector{Tuple{String,DateTime}}  # available METADATA commits
    general_commits::Vector{Tuple{String,DateTime}}   # available General commits
    current_index::Int  # current position in active repo's commit list
end

function Base.show(io::IO, r::RepositoryState)
    repo_name = r.active_repo == METADATA ? "METADATA" : "General"
    total_commits = r.active_repo == METADATA ? length(r.metadata_commits) : length(r.general_commits)
    println(io, "RepositoryState($(repo_name) @ $(r.commit[1:7]), $(r.current_index)/$(total_commits))")
end

export Dependencies, DependenciesDelta, RepositoryState
export dependencies, next_commit!, first_commit

const TRANSITION_DATE = DateTime("2018-02-25T22:29:39")
const TRANSITION_COMMIT = "fdea9f164d45b616ce775e5506c0bbef70f3bb29"

const _git_base_dir = get(ENV, "JULIA_PACKAGE_DEPENDENCIES_CLONEDIR", pwd())

# Global state
const _package_index = Ref{Dict{String,Int}}()
const _reverse_index = Ref{Dict{Int,String}}()
const _metadata_commits = Ref{Vector{Tuple{String,DateTime}}}()
const _general_commits = Ref{Vector{Tuple{String,DateTime}}}()
const _current_repo_state = Ref{Union{Nothing,RepositoryState}}(nothing)
const _initialized = Ref{Bool}(false)

""" 
Verify that we have all the two repositories cloned in _git_base_dir and throw an error with the
cloning instructions if not, also, reset to a known commit. Initialize the locks if we are using them. 
Throw an error if we can't acquire the lock and setup code to release it when the module is unloaded. 
"""
function _verify_state()
    metadata_path = joinpath(_git_base_dir, "METADATA")
    general_path = joinpath(_git_base_dir, "General")
    
    if !isdir(metadata_path)
        error("""
        METADATA repository not found at $metadata_path
        Please clone it with:
        cd $_git_base_dir
        git clone https://github.com/JuliaLang/METADATA.jl METADATA
        """)
    end
    
    if !isdir(general_path)
        error("""
        General repository not found at $general_path
        Please clone it with:
        cd $_git_base_dir
        git clone https://github.com/JuliaRegistries/General.git General
        """)
    end
    
    # Load package index
    index_file = joinpath(_git_base_dir, "combined_package_index.json")
    if !isfile(index_file)
        error("Combined package index not found at $index_file. Please run build_combined_package_index.jl first.")
    end
    
    index_data = JSON.parsefile(index_file)
    _package_index[] = Dict{String,Int}()
    _reverse_index[] = Dict{Int,String}()
    
    for (name, data) in index_data["package_metadata"]
        idx = data["index"]
        _package_index[][name] = idx
        _reverse_index[][idx] = name
    end
    
    # Get all commits from both repositories
    metadata_commits_all = _get_all_commits(joinpath(_git_base_dir, "METADATA"))
    general_commits_all = _get_all_commits(joinpath(_git_base_dir, "General"))
    
    # Filter commits after transition date for General repo
    _general_commits[] = filter(x -> x[2] >= TRANSITION_DATE, general_commits_all)
    # Filter commits before transition date for METADATA repo  
    _metadata_commits[] = filter(x -> x[2] < TRANSITION_DATE, metadata_commits_all)
    
    _initialized[] = true
    
    return nothing
end

function _get_package_id(name::String)
    if !haskey(_package_index[], name)
        error("Package '$name' not found in package index")
    end
    return _package_index[][name]
end

function _get_package_name(id::Int)
    if !haskey(_reverse_index[], id)
        error("Package ID $id not found in reverse index")
    end
    return _reverse_index[][id]
end

function _version_in_range(version::String, version_range::String)
    """Check if a version falls within a given version range using Julia's Pkg types."""
    try
        # Parse current version
        current_version = Pkg.Types.VersionNumber(version)
        
        # Parse version range using Julia's VersionRange
        parsed_range = Pkg.Types.VersionRange(version_range)
        
        # Check if version is in range
        return current_version in parsed_range
        
    catch
        # Fallback to string comparison for malformed versions
        return version == version_range
    end
end

function _get_all_commits(repo_path::String)
    """Get all commits from a git repository with timestamps."""
    if !isdir(repo_path)
        error("Repository not found: $repo_path")
    end
    
    # Change to repo directory and run git command
    old_pwd = pwd()
    result = ""
    cd(repo_path)
    try
        # First, ensure we're on the right branch
        if basename(repo_path) == "METADATA"
            run(pipeline(`git checkout metadata-v2 --force`, stdout=devnull, stderr=devnull))
        else
            run(pipeline(`git checkout master --force`, stdout=devnull, stderr=devnull))
        end
        
        cmd = `git log --first-parent --date=raw --pretty=format:%H\ %cd --reverse`
        result = read(cmd, String)
    finally
        cd(old_pwd)
    end
    
    commits = Tuple{String,DateTime}[]
    for line in split(strip(result), '\n')
        if isempty(strip(line))
            continue
        end
        parts = split(line, ' ', limit=3)
        if length(parts) >= 2
            hash = parts[1]
            # Parse raw git timestamp: "unix_timestamp timezone_offset"
            unix_timestamp = parse(Int, parts[2])
            # Convert Unix timestamp to DateTime (automatically UTC)
            dt = unix2datetime(unix_timestamp)
            push!(commits, (hash, dt))
        end
    end
    
    return commits
end

function _checkout_commit(repo_path::String, commit_hash::String)
    """Checkout a specific commit in the repository."""
    old_pwd = pwd()
    cd(repo_path)
    try
        cmd = `git checkout --force $commit_hash`
        run(pipeline(cmd, stdout=devnull, stderr=devnull))
    finally
        cd(old_pwd)
    end
end

function _extract_dependencies_from_repo(repo_path::String, is_metadata::Bool)
    """Extract dependencies from current repository state."""
    package_deps = Dict{String,Set{String}}()
    
    if is_metadata
        # METADATA.jl format: packages in subdirectories
        for entry in readdir(repo_path)
            pkg_dir = joinpath(repo_path, entry)
            if !isdir(pkg_dir) || startswith(entry, ".")
                continue
            end
            
            # Find versions directory
            versions_dir = joinpath(pkg_dir, "versions")
            if !isdir(versions_dir)
                continue
            end
            
            # Get latest version
            versions = readdir(versions_dir)
            if isempty(versions)
                continue
            end
            
            # Simple version sorting (could be improved with semantic versioning)
            latest_version = maximum(versions)
            
            # Read requires file
            requires_file = joinpath(versions_dir, latest_version, "requires")
            if isfile(requires_file)
                deps = Set{String}()
                for line in readlines(requires_file)
                    line = strip(line)
                    if !isempty(line) && !startswith(line, "#")
                        dep_name = split(line)[1]
                        if dep_name != "julia"  # Skip julia version requirement
                            push!(deps, dep_name)
                        end
                    end
                end
                if !isempty(deps)
                    package_deps[entry] = deps
                end
            end
        end
    else
        # General registry format: Registry.toml + package subdirs
        for letter_dir in readdir(repo_path)
            letter_path = joinpath(repo_path, letter_dir)
            if !isdir(letter_path) || length(letter_dir) != 1 || !isletter(letter_dir[1])
                continue
            end
            
            for pkg_name in readdir(letter_path)
                pkg_dir = joinpath(letter_path, pkg_name)
                if !isdir(pkg_dir)
                    continue
                end
                
                # Read Package.toml for metadata
                package_toml = joinpath(pkg_dir, "Package.toml")
                if !isfile(package_toml)
                    continue
                end
                
                # Read Deps.toml for dependencies  
                deps_toml = joinpath(pkg_dir, "Deps.toml")
                if !isfile(deps_toml)
                    continue
                end
                
                try
                    deps_data = TOML.parsefile(deps_toml)
                    
                    # Get all available versions from Versions.toml
                    versions_toml = joinpath(pkg_dir, "Versions.toml")
                    if !isfile(versions_toml)
                        continue
                    end
                    
                    versions_data = TOML.parsefile(versions_toml)
                    if isempty(versions_data)
                        continue
                    end
                    
                    # Find latest version (simple string comparison for now)
                    latest_version = maximum(keys(versions_data))
                    
                    # Extract dependencies using proper version range matching
                    current_deps = Set{String}()
                    
                    # Check all version ranges to see which apply to the latest version
                    for (version_range, deps) in deps_data
                        if !isa(deps, Dict)
                            continue
                        end
                        
                        # Check if latest version falls within this version range
                        if _version_in_range(latest_version, version_range)
                            # Add dependencies from this version range
                            for dep_name in keys(deps)
                                if dep_name != "julia"  # Skip julia deps
                                    push!(current_deps, dep_name)
                                end
                            end
                        end
                    end
                    
                    if !isempty(current_deps)
                        package_deps[pkg_name] = current_deps
                    end
                catch e
                    # Skip packages with parsing errors
                    continue
                end
            end
        end
    end
    
    return package_deps
end

function _build_dependency_graph(package_deps::Dict{String,Set{String}})
    """Build a dependency graph from package dependencies."""
    package_nodes = Dict{String,Int}()
    edges = Tuple{Int,Int}[]
    
    # Only include packages that exist in our index
    for (pkg_name, deps) in package_deps
        if haskey(_package_index[], pkg_name)
            pkg_id = _get_package_id(pkg_name)
            package_nodes[pkg_name] = pkg_id
            
            for dep_name in deps
                if haskey(_package_index[], dep_name)
                    dep_id = _get_package_id(dep_name)
                    push!(edges, (pkg_id, dep_id))
                end
            end
        end
    end
    
    # Create graph
    max_id = maximum(values(_package_index[]))
    g = SimpleDiGraph(max_id)
    
    for (src, dst) in edges
        add_edge!(g, src, dst)
    end
    
    return g, package_nodes
end

"""
Load dependencies for a specific date/commit. Returns Dependencies object.
"""
function dependencies(target_date::DateTime)
    if !_initialized[]
        _verify_state()
    end
    
    # Find the appropriate repository and commit
    if target_date < TRANSITION_DATE
        # Use METADATA repository
        commits = _metadata_commits[]
        repo_path = joinpath(_git_base_dir, "METADATA")
        is_metadata = true
        active_repo = :METADATA
    else
        # Use General repository  
        commits = _general_commits[]
        repo_path = joinpath(_git_base_dir, "General")
        is_metadata = false
        active_repo = :GENERAL
    end
    
    # Find commit closest to target date
    if isempty(commits)
        error("No commits available for target date $target_date")
    end
    
    commit_idx = 1
    for (i, (hash, dt)) in enumerate(commits)
        if dt <= target_date
            commit_idx = i
        else
            break
        end
    end
    
    commit_hash, commit_dt = commits[commit_idx]
    
    # Checkout the commit
    _checkout_commit(repo_path, commit_hash)
    
    # Extract dependencies
    package_deps = _extract_dependencies_from_repo(repo_path, is_metadata)
    
    # Build graph
    g, package_nodes = _build_dependency_graph(package_deps)
    
    # Store current state
    _current_repo_state[] = RepositoryState(
        commit_hash, commit_dt, is_metadata ? METADATA : GENERAL,
        _metadata_commits[], _general_commits[], commit_idx
    )
    
    return Dependencies(g, commit_hash, commit_dt, active_repo, package_nodes)
end

function dependencies(date_str::String)
    return dependencies(DateTime(date_str))
end

function dependencies(commit_hash::String)
    if !_initialized[]
        _verify_state()
    end
    
    # Find which repository contains this commit
    metadata_commits = _metadata_commits[]
    general_commits = _general_commits[]
    
    commit_dt = nothing
    commit_idx = 0
    repo_path = ""
    is_metadata = false
    active_repo = :GENERAL
    
    # Check METADATA commits
    for (i, (hash, dt)) in enumerate(metadata_commits)
        if hash == commit_hash
            commit_dt = dt
            commit_idx = i
            repo_path = joinpath(_git_base_dir, "METADATA")
            is_metadata = true
            active_repo = :METADATA
            break
        end
    end
    
    # Check General commits if not found
    if commit_dt === nothing
        for (i, (hash, dt)) in enumerate(general_commits)
            if hash == commit_hash
                commit_dt = dt
                commit_idx = i
                repo_path = joinpath(_git_base_dir, "General")
                is_metadata = false
                active_repo = :GENERAL
                break
            end
        end
    end
    
    if commit_dt === nothing
        error("Commit $commit_hash not found in either repository")
    end
    
    # Checkout and extract
    _checkout_commit(repo_path, commit_hash)
    package_deps = _extract_dependencies_from_repo(repo_path, is_metadata)
    g, package_nodes = _build_dependency_graph(package_deps)
    
    # Store current state
    _current_repo_state[] = RepositoryState(
        commit_hash, commit_dt, is_metadata ? METADATA : GENERAL,
        metadata_commits, general_commits, commit_idx
    )
    
    return Dependencies(g, commit_hash, commit_dt, active_repo, package_nodes)
end

"""
Move to the next commit and return the updated Dependencies and the delta.
"""
function next_commit!(d::Dependencies)
    if !_initialized[]
        _verify_state()
    end
    
    if _current_repo_state[] === nothing
        error("No current repository state. Load dependencies first.")
    end
    
    current_state = _current_repo_state[]
    
    # Determine next commit
    if current_state.active_repo == METADATA
        commits = current_state.metadata_commits
        repo_path = joinpath(_git_base_dir, "METADATA")
        is_metadata = true
        
        if current_state.current_index < length(commits)
            next_idx = current_state.current_index + 1
            next_commit_hash, next_dt = commits[next_idx]
            
            # Check if we need to transition to General repo
            if next_dt >= TRANSITION_DATE
                # Transition to General repository
                commits = current_state.general_commits
                next_idx = 1
                next_commit_hash, next_dt = commits[next_idx]
                repo_path = joinpath(_git_base_dir, "General")
                is_metadata = false
            end
        else
            # Transition to General repo
            commits = current_state.general_commits
            next_idx = 1
            next_commit_hash, next_dt = commits[next_idx]
            repo_path = joinpath(_git_base_dir, "General")
            is_metadata = false
        end
    else
        # Currently in General repo
        commits = current_state.general_commits
        repo_path = joinpath(_git_base_dir, "General")
        is_metadata = false
        
        if current_state.current_index < length(commits)
            next_idx = current_state.current_index + 1
            next_commit_hash, next_dt = commits[next_idx]
        else
            error("No more commits available")
        end
    end
    
    # Checkout and extract new state
    _checkout_commit(repo_path, next_commit_hash)
    new_package_deps = _extract_dependencies_from_repo(repo_path, is_metadata)
    new_g, new_package_nodes = _build_dependency_graph(new_package_deps)

    # ## Dump all edges in d.g
    # for edge in edges(d.g)
    #     src_name = _get_package_name(src(edge))
    #     dst_name = _get_package_name(dst(edge))
    #     @debug "Edge in old graph: $src_name -> $dst_name"
    # end

    # ## Dump all edges in new_g
    # for edge in edges(new_g)
    #     src_name = _get_package_name(src(edge))
    #     dst_name = _get_package_name(dst(edge))
    #     @debug "Edge in new graph: $src_name -> $dst_name"
    # end
    
    active_repo_sym = is_metadata ? :METADATA : :GENERAL
    new_deps = Dependencies(new_g, next_commit_hash, next_dt, active_repo_sym, new_package_nodes)
    
    # Calculate delta
    old_packages = Set(keys(d.packages))
    new_packages = Set(keys(new_deps.packages))
    
    added_packages = collect(setdiff(new_packages, old_packages))
    removed_packages = collect(setdiff(old_packages, new_packages))
    
    # Calculate edge differences
    old_edges = Set{Tuple{Int,Int}}()
    for edge in edges(d.g)
        push!(old_edges, (src(edge), dst(edge)))
    end
    
    new_edges_set = Set{Tuple{Int,Int}}()
    for edge in edges(new_deps.g)
        push!(new_edges_set, (src(edge), dst(edge)))
    end
    
    added_edges = collect(setdiff(new_edges_set, old_edges))
    removed_edges = collect(setdiff(old_edges, new_edges_set))
    
    # Update current state
    _current_repo_state[] = RepositoryState(
        next_commit_hash, next_dt, is_metadata ? METADATA : GENERAL,
        current_state.metadata_commits, current_state.general_commits, next_idx
    )
    
    delta = DependenciesDelta(
        added_packages,
        removed_packages,
        added_edges,
        removed_edges,
        next_dt,
        next_commit_hash,
        active_repo_sym
    )
    
    return new_deps, delta
end

"""
Get the first available commit from the METADATA repository.
"""
function first_commit()
    if !_initialized[]
        _verify_state()
    end
    
    if isempty(_metadata_commits[])
        error("No METADATA commits available")
    end
    
    first_hash, first_dt = _metadata_commits[][1]
    return dependencies(first_hash)
end

function __init__()
    # Module initialization
    if !_initialized[]
        try
            _verify_state()
        catch e
            @warn "JuliaPackageDependencies initialization failed: $e"
        end
    end
end

end # module