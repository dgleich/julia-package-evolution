## Write a bunch of utility functions.

using JSON
using SparseArrays
using Dates
using Graphs
using Graphs, GraphMakie, CairoMakie

function read_smat(filename)
  open(filename, "r") do f
    # Read header line
    line = readline(f)
    parts = split(line)
    m = parse(Int, parts[1])
    n = parse(Int, parts[2])
    nnz = parse(Int, parts[3])
    
    # Initialize COO format
    rows = Int[]
    cols = Int[]
    vals = Int[]
    
    # Read data lines
    for _ in 1:nnz
      line = readline(f)
      parts = split(line)
      # Convert from 0-indexed to 1-indexed
      row = parse(Int, parts[1]) + 1
      col = parse(Int, parts[2]) + 1
      val = parse(Int, parts[3])
      push!(rows, row)
      push!(cols, col)
      push!(vals, val)
    end
    
    # Create and return sparse matrix
    return sparse(rows, cols, vals, m, n)
  end
end

function _extract_date_from_filename(filename)
  # Extract YYYY-MM from filename
  match_result = match(r"adj_(\d{4}-\d{2})\.smat", basename(filename))
  if match_result !== nothing
      date_str = match_result[1]
      return Date(date_str * "-01")
  else
      return nothing
  end
end

function _load_package_index(index_file=joinpath(@__DIR__, "combined_package_index.json"))
  if isfile(index_file)
    index_data = open(index_file, "r") do io
      JSON.parse(io)
    end
  
    # Create mapping from package names to indices
    package_to_index = Dict{String, Int}()
    for (pkg, info) in index_data["package_metadata"]
      package_to_index[pkg] = info["index"]
    end
    
    # Create reverse mapping from indices to package names
    index_to_package = Dict{Int, String}()
    for (pkg, idx) in package_to_index
      index_to_package[idx] = pkg
    end
  
    return (;index_to_package, package_to_index)
  else
    @error "Package index file not found: $index_file"
  end
end


function load_dependencies_info(matrix_dir=joinpath(@__DIR__, "matrices_fixed"))

  indices = _load_package_index() 

  matrix_files = filter(f -> endswith(f, ".smat"), readdir(matrix_dir, join=true))
  date_matrix_pairs = [(_extract_date_from_filename(f), f) for f in matrix_files]
  filter!(pair -> pair[1] !== nothing, date_matrix_pairs)
  graphs = map(date_matrix_pairs) do pair 
    date, matrix_file  = pair 
    A = read_smat(matrix_file)
    G = SimpleDiGraph(A) 
    return date, G 
  end 
  display(graphs)

  info = (; graphs, indices...)
  return info
end 

""" Return the set of all recursive dependencies for a given package index 
    This will return all packages that depend on the given package, directly or indirectly.
"""
function package_subgraph(g::SimpleDiGraph, index)
  # Create a subgraph containing all nodes reachable from the given index
  subgraph_nodes = Set{Int}()
  queue = [index]
  
  while !isempty(queue)
    current = popfirst!(queue)
    if current in subgraph_nodes
      continue
    end
    push!(subgraph_nodes, current)
    
    # Get neighbors (dependencies) of the current node
    for neighbor in outneighbors(g, current)
      if !(neighbor in subgraph_nodes)
        push!(queue, neighbor)
      end
    end
  end
  
  return induced_subgraph(g, collect(subgraph_nodes))
end 

function package_subgraph(info, package_name)
  # find the index of the package
  package_index = info.package_to_index[package_name]
  if isnothing(package_index)
    @error "Package $package_name not found in index"
  end

  return map(info.graphs) do (date, g)
    subgraph = package_subgraph(g, package_index)
    return (date, subgraph)
  end
end 

function _checked_index(info, package_name)
  # Check if the package exists in the index
  if !haskey(info.package_to_index, package_name)
    @error "$package_name not found in package index"
  end
  
  return info.package_to_index[package_name]
end

function print_deps_over_time(info, package_name)
  index = _checked_index(info, package_name)
  
  for (date, g) in info.graphs 
    deps = outneighbors(g, index)
    # decode deps into a list of package names
    package_names = [info.index_to_package[dep] for dep in deps]  
    # Print combined data and dependency info
    println("Date: $date, Package: $package_name, Dependencies: $(length(package_names))")
    for dep in package_names
      println("  - $dep")
    end
  end
end