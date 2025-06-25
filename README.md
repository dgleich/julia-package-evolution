# Temporal Julia Package Analysis

This project aims to build and analyze the temporal evolution of the Julia package dependency graph over time. By leveraging the historical data from both the original METADATA.jl and the current General registry, we can understand how the package ecosystem has evolved from Julia's early days to the present.

## Project Goals

1. Track package dependencies over time using the complete history of Julia package registries
2. Build temporal adjacency structures to represent changing package dependencies
3. Analyze the evolution of the Julia package ecosystem
4. Identify important packages and their relationships over time
5. Study the transition between METADATA.jl and General registry

## Components

### Data Collection
- `index_commits_by_time.py`: Python script to index commits by time (daily and monthly) for the General registry
- `index_metadata_commits.py`: Python script to index commits for the METADATA.jl registry
- `extract_dependencies.py`: Python script to extract package dependencies from the General registry at specific commits
- `extract_metadata_dependencies.py`: Python script to extract package dependencies from METADATA.jl at specific commits
- `build_monthly_dependencies.py`: Python script to build dependency snapshots for each month from the General registry
- `build_metadata_monthly_dependencies.py`: Python script to build dependency snapshots for METADATA.jl

### Data Processing
- `build_combined_package_index.jl`: Julia script to build a comprehensive package index across both registries and all time periods
- `build_fixed_adjacency_matrices.jl`: Julia script to build adjacency matrices with proper handling of both registry formats

### Analysis
- `analyze_dependencies.jl`: Julia script to analyze dependencies for specific packages
- `plot_visualization_deps.jl`: Julia script to analyze and plot dependencies on visualization packages over time
- `analyze_skipped_deps.jl`: Julia script to analyze which dependencies are skipped during matrix generation

### Testing and Validation
- `test_all_packages.py`: Comprehensive test suite for dependency extraction validation
- `test_dependency_extraction.py`: Core dependency extraction testing framework

## Usage Instructions

1. **Clone both package registries and index commits by time**:
   ```bash
   # For General registry
   git clone https://github.com/JuliaRegistries/General.git
   python3 index_commits_by_time.py
   
   # For METADATA.jl registry
   git clone https://github.com/JuliaLang/METADATA.jl METADATA
   python3 index_metadata_commits.py
   ```
   This will produce `commits_by_day.json`, `commits_by_month.json`, and `metadata_commits_by_month.json`.

2. **Extract package dependencies for each month from both registries**:
   ```bash
   # For General registry
   python3 build_monthly_dependencies.py
   
   # For METADATA.jl registry
   python3 build_metadata_monthly_dependencies.py
   ```
   This will generate `dependencies_YYYY-MM.json` and `metadata_dependencies_YYYY-MM.json` files for each month.

3. **Build a comprehensive package index across both registries**:
   ```bash
   julia build_combined_package_index.jl
   ```
   This creates `combined_package_index.json` with a global index for all packages from both registries.

4. **Generate sparse adjacency matrices with proper handling of both formats**:
   ```bash
   julia build_fixed_adjacency_matrices.jl
   ```
   This produces SMAT format files in the `matrices_fixed/` directory, one for each month.

5. **Analyze visualization package dependencies over time**:
   ```bash
   julia plot_visualization_deps.jl
   ```
   This generates plots showing the growth of dependencies on key visualization packages.

6. **Analyze skipped dependencies**:
   ```bash
   julia analyze_skipped_deps.jl
   ```
   This identifies which dependencies are being skipped during matrix generation (typically Julia standard libraries).

7. **Validate dependency extraction**:
   ```bash
   python3 test_all_packages.py
   ```
   This runs comprehensive tests to validate dependency extraction accuracy across multiple packages and versions.

## How it works

The project uses a combination of Python (for git operations and initial data extraction) and Julia (for dependency analysis and visualization). We leverage the fact that both Julia registries (METADATA.jl and General) are stored in git, allowing us to reconstruct the state of package dependencies at any point in time.

1. We first identify relevant commits in both registries at regular time intervals
2. For each time point, we extract the package dependencies based on the appropriate registry structure
   - METADATA.jl (used before February 25, 2018) has its own format
   - General registry (used after February 25, 2018) uses a different format with UUIDs
3. We create a consistent package index across both registries and all time points, preserving temporal ordering
4. We generate sparse adjacency matrices for each time point using the consistent index, properly handling the format differences
5. These matrices can then be analyzed to study the evolution of the package ecosystem

## Registry Transition

The Julia package ecosystem underwent a significant change on February 25, 2018 (commit `fdea9f164d45b616ce775e5506c0bbef70f3bb29`), when the package registration system switched from METADATA.jl to the General registry. This introduced several changes:

1. **Format change**: The General registry uses a different format with UUIDs as primary identifiers
2. **Dependency representation**: In METADATA.jl, dependencies are stored with synthetic UUIDs and package names, while in General, they use real UUIDs
3. **Handling both formats**: The project's scripts handle both formats correctly, ensuring a seamless transition in the analysis

## Requirements

- Python 3.x with `tomllib` module (Python 3.11+ or with `tomli` package)
- Julia 1.x with the following packages:
  - SparseArrays (standard library)
  - JSON
  - Dates (standard library)
  - Plots (for visualization)
- Git

## File Formats

- **SMAT format**: Simple sparse matrix format with header line `rows cols nnz` followed by one line per nonzero with `row col value` (0-indexed)
- **JSON dependency files**: 
  - `metadata_dependencies_YYYY-MM.json`: METADATA.jl dependencies with package names
  - `dependencies_YYYY-MM.json`: General registry dependencies with UUIDs

## Fixed Bugs and Improvements

### Version-Specific Dependency Extraction (December 2024)
- **Fixed critical bug in `extract_dependencies.py`** where version-specific dependencies were incorrectly flattened
  - **Problem**: Script was aggregating dependencies from ALL version ranges instead of only those applicable to the target version
  - **Example**: MatrixNetworks.jl was incorrectly showing both Arpack AND GenericArpack, when v1.0.4 should only have GenericArpack
  - **Solution**: Implemented proper version range matching logic that:
    - Uses semantic version comparison (not string comparison)  
    - Correctly handles Julia's compressed dependency format
    - Accumulates dependencies only from applicable version ranges
    - Supports various range formats: `"0-2"`, `"1.0.3-1"`, `"0.22-0"`, etc.

### Comprehensive Testing Framework
- **Added robust test suite** with `test_all_packages.py` validating 6 major Julia packages
- **Multi-version testing** confirms accuracy across package evolution (e.g., Plots.jl v0.14.0 vs v1.40.13)
- **Julia stdlib filtering** excludes standard libraries from dependency comparisons 
- **100% test pass rate** across 15 test scenarios covering different package types and time periods

### Registry Format Compatibility  
- Fixed issue in `build_fixed_adjacency_matrices.jl` where General registry dependencies were incorrectly processed
  - The problem was that the script was treating the key-value pairs in General registry dependencies incorrectly
  - In General registry, keys are package names and values are UUIDs
  - Fixed by reversing the interpretation of dependency structure for General registry files

## Future Work

1. Regenerate the combined package index to include recently added packages (like QuantitativeSusceptibilityMappingTGV)
2. Analyze network properties of the dependency graphs over time
3. Identify "core" packages that form the foundation of the ecosystem
4. Visualize the growth and evolution of the ecosystem
