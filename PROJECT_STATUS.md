# Julia Package Evolution - Project Status

## What We've Accomplished

1. ✅ Set up project repository and pushed to GitHub: https://github.com/dgleich/julia-package-evolution
2. ✅ Created scripts to map commits to time periods for both registries:
    - `index_commits_by_time.py`: For General registry (92 unique months)
    - `index_metadata_commits.py`: For METADATA.jl registry (extending coverage back to 2012)
3. ✅ Identified major structural changes in Julia registries over time (documented in REGISTRY_CHANGES.md)
    - Early structure used lowercase filenames (package.toml, dependencies.toml, etc.)
    - Later structure uses capitalized filenames (Package.toml, Deps.toml, etc.)
    - Different dependency formats between METADATA.jl and General registry
    - Hash format changed from `hash-sha1` to `git-tree-sha1`

## Recent Progress

1. ✅ Expanded data collection to include METADATA.jl registry:
   - Created extraction scripts for both registries: `extract_dependencies.py` and `extract_metadata_dependencies.py`
   - Successfully extracted dependencies all the way back to Julia's early days (2012)
   - Integrated both registries into a unified timeline spanning 2012-2025

2. ✅ Fixed critical bug in adjacency matrix generation:
   - Identified incorrect processing of General registry dependencies
   - General registry format has package names as keys and UUIDs as values (opposite of what was assumed)
   - Fixed bug in `build_fixed_adjacency_matrices.jl` to correctly process both registry formats
   - Successfully generated complete adjacency matrices for all 152 months (2012-08 to 2025-05)

3. ✅ Created visualization of key package dependencies:
   - Created `plot_visualization_deps.jl` to track dependencies on important packages over time
   - Analyzed the growth of Plots.jl (508 dependent packages) vs Makie.jl (125 dependent packages)
   - Generated clear visualization showing adoption trends

4. ✅ Analyzed skipped dependencies:
   - Created `analyze_skipped_deps.jl` to investigate missing dependencies
   - Identified that most skipped dependencies (17,836 in May 2025) are Julia standard libraries
   - Found one legitimate missing package (QuantitativeSusceptibilityMappingTGV) added after index creation

## Next Steps

1. 📝 Regenerate combined package index to include recently added packages:
   - Update `combined_package_index.json` to include all packages through May 2025
   - Regenerate adjacency matrices with the updated index

2. 📝 Analyze network properties of the dependency graphs over time:
   - Compute centrality metrics to identify core packages
   - Analyze clustering and community structure
   - Track the evolution of dependency patterns

3. 📝 Create comprehensive visualizations:
   - Interactive visualizations of the package ecosystem
   - Animated timeline showing growth over time
   - Visualize the transition between METADATA.jl and General registry periods

4. 📝 Perform focused analysis on specific domains:
   - Machine learning/AI packages
   - Data science ecosystem
   - Web development stack
   - Scientific computing foundations

## Technical Insights

- Registry transition occurred on February 25, 2018 (commit `fdea9f164d45`)
- METADATA.jl and General registry use different dependency formats:
  - METADATA.jl: Synthetic UUIDs as keys, package names as values
  - General: Package names as keys, real UUIDs as values
- Standard libraries (e.g., LinearAlgebra, Random) are not tracked in package registries
- Properly handling both formats is crucial for accurate temporal analysis

## Data Files Generated

- `commits_by_month.json`: First commit of each month from General registry
- `metadata_commits_by_month.json`: First commit of each month from METADATA.jl
- `dependencies_YYYY-MM.json`: Package dependency data for each month from General registry
- `metadata_dependencies_YYYY-MM.json`: Package dependency data for each month from METADATA.jl
- `combined_package_index.json`: Global index of all packages across both registries
- `matrices_fixed/adj_YYYY-MM.smat`: Sparse adjacency matrices for each month in SMAT format