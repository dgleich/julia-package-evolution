# Julia Package Evolution - Project Status

## What We've Accomplished

1. ✅ Set up project repository and pushed to GitHub: https://github.com/dgleich/julia-package-evolution
2. ✅ Created `index_commits_by_time.py` script to map commits to time periods (days/months)
    - Successfully extracted monthly commit data (92 unique months)
    - Successfully extracted daily commit data (2636 unique days)
3. ✅ Identified major structural changes in the Julia Registry over time (documented in REGISTRY_CHANGES.md)
    - Early structure used lowercase filenames (package.toml, dependencies.toml, etc.)
    - Later structure uses capitalized filenames (Package.toml, Deps.toml, etc.)
    - Hash format changed from `hash-sha1` to `git-tree-sha1`
    - Dependencies and compatibility format evolved

## Next Steps

1. ✅ Implement `extract_dependencies.py` script that can:
   - Handle both early and late registry formats
   - Extract package dependency information at any given commit
   - Save dependency data in a structured JSON format
   - Successfully tested on May 2025 commit (12,151 packages: 10,580 regular + 1,571 JLL)

2. 📝 Validate dependency extraction and create network visualization:
   - Test extraction on early registry format (2017-2018 commits)
   - Create network graph visualization of package dependencies
   - Verify data quality and completeness

3. 📝 Create Julia code for building and analyzing the temporal adjacency structure:
   - Load dependency data from multiple time points
   - Build graph representations
   - Analyze how package relationships evolve over time
   - Visualize key metrics (centrality, clusters, etc.)

4. 📝 Run analysis on significant time points:
   - Start with monthly snapshots for a high-level view
   - Dive into specific periods of interest with daily snapshots
   - Focus on major Julia releases or ecosystem shifts

## Technical Considerations

- The registry format changed around 2019, so the dependency extraction code needs to handle both formats
- Working with the full history requires careful Git operations (the repo is quite large)
- For meaningful temporal analysis, proper dating of dependencies is crucial

## Data Files Generated

- `commits_by_month.json`: First commit of each month
- `commits_by_day.json`: First commit of each day