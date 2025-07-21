## This script visualizes the dependency tree of a Julia package using Graphviz.
include("visualize_deps_tree.jl"); 
visualize_dependency_tree("GLMakie", 3; ego_net=true, exclude_packages=["Makie"])

##
