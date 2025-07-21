using Graphs
using SparseArrays
using LinearAlgebra
using Dates 
using GraphPlayground
include("temporal_ecosystem_viz.jl"); 
results = analyze_glmakie()
mats = results["temporal_graphs"]

## Look at the graph with the default coordinates
# we can use the default coordinates to visualize the graph
g = 
##
# Now let's form the union graph and visualize iterations
function form_union(results)
  # let's add together all the sparse matrices from all the temporal graphs)
  mats = results["temporal_graphs"]
  union_graph = first(mats)[2] # this shoudl be the first matrix. 
  for key in keys(mats)
    union_graph += mats[key]
  end
  # set all the values to be 1
  union_graph.nzval .= 1 
  return union_graph
end 
ug, uglabels = subgraph(form_union(results), results)
p = playground(ug, labels=uglabels, graphplot_options = (;node_color=results["node_colors"]))

## save the positions! 

## Show the plot over time...



## Assume that this is "okay" and has the right deps for all the cases, let's extract the matrices...
# build a graph structure from the matrix along with the node labels
function show_matrix(m, lbls)
  # m is a sparse matrix, lbls is a vector of labels,
  # but we want to restrict to only those nodes used in the matrix
  ei, ej = findnz(m)[1:2]
  ids = union(ei, ej)
  labels = map(id -> lbls[id], ids)
  # relabel the graph 
  id2small = Dict{Int,Int}(ids .=> 1:length(ids))
  si = map(id -> id2small[id], ei)
  sj = map(id -> id2small[id], ej)
  sm = sparse(si, sj, 1, length(ids), length(ids))
  g = SimpleDiGraph(sm) 
  playground(g, labels=labels)
end
show_matrix(mats["2020-10"], results["labels"])



##
pts = Point2f.(zip(results["pos_x"], results["pos_y"]))
function _extract_graph(results, graph_matrix) 
  # relabel the nodes
  ei,ej = findnz(graph_matrix) 
  nodemap = results["orig_to_graph"]
  newei = map(ei) do i
    nodemap[i]
  end
  newej = map(ej) do j
    nodemap[j]
  end
  g = Graph(Edge.(newei,newej))
  nfull = length(results["graph_to_orig"])
  while nv(g) < nfull
    add_vertex!(g)
  end
  return g
end
lbls = results["labels"]
G = _extract_graph(results, results["temporal_graphs"]["2025-04"])
using GLMakie 
graphplot(G, layout=pts, node_color=results["node_colors"])

##
function show_temporal_graphs(results)
  # sort the Dates
  dates = sort(collect(keys(results["temporal_graphs"])))
  pts = Point2f.(zip(results["pos_x"], results["pos_y"]))

  # let's visualize the temporal graphs
  for date in dates 
    println("Showing graph for date: ", date)
    G = _extract_graph(results, results["temporal_graphs"][date])
    p = graphplot(G, layout=pts, node_color=results["node_colors"])
    p.axis.title = "Graph for date: $date"
    display(p)
    sleep(1.0) # pause for a second to see the graph
  end
end
show_temporal_graphs(results)

##
