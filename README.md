# Temporal Julia Package Analysis

This project aims to build and analyze the temporal evolution of the Julia package dependency graph over time. By leveraging the historical data in the Julia Registry, we can understand how the package ecosystem has evolved.

## Project Goals

1. Track package dependencies over time using the JuliaRegistries/General git history
2. Build temporal adjacency structures to represent changing package dependencies
3. Analyze the evolution of the Julia package ecosystem
4. Identify important packages and their relationships over time

## Components

- `index_commits_by_time.py`: Python script to index commits by time (daily and monthly)
- `extract_dependencies.py`: Python script to extract package dependencies from the Julia Registry at specific commits
- `build_monthly_dependencies.py`: Python script to build dependency snapshots for each month
- `build_package_index.jl`: Julia script to build a comprehensive package index across all time periods
- `build_adjacency_matrices.jl`: Julia script to build sparse adjacency matrices for each month using a consistent package index
- `analyze_dependencies.jl`: Julia script to analyze dependencies for specific packages

## Usage Instructions

1. **Clone the Julia Registry and index commits by time**:
   ```bash
   git clone https://github.com/JuliaRegistries/General.git
   python3 index_commits_by_time.py
   ```
   This will produce `commits_by_day.json` and `commits_by_month.json`.

2. **Extract package dependencies for each month**:
   ```bash
   python3 build_monthly_dependencies.py
   ```
   This will generate `dependencies_YYYY-MM.json` files for each month.

3. **Build a consistent package index**:
   ```bash
   julia build_package_index.jl
   ```
   This creates `package_index.json` with a global index for all packages.

4. **Generate sparse adjacency matrices**:
   ```bash
   julia build_adjacency_matrices.jl
   ```
   This produces SMAT format files in the `matrices/` directory, one for each month.

5. **Analyze specific packages**:
   ```bash
   julia analyze_dependencies.jl
   ```
   This can be customized to analyze dependencies for specific packages.

## How it works

The project uses a combination of Python (for git operations and initial data extraction) and Julia (for dependency analysis and visualization). We leverage the fact that the Julia Registry is stored in git, allowing us to reconstruct the state of package dependencies at any point in time.

1. We first identify relevant commits in the Julia Registry at regular time intervals
2. For each time point, we extract the package dependencies based on the registry structure
3. We create a consistent package index across all time points, preserving temporal ordering
4. We generate sparse adjacency matrices for each time point using the consistent index
5. These matrices can then be analyzed to study the evolution of the package ecosystem

## Requirements

- Python 3.x with `tomllib` module (Python 3.11+ or with `tomli` package)
- Julia 1.x with SparseArrays and JSON packages
- Git

## File Formats

- **SMAT format**: Simple sparse matrix format with header line `rows cols nnz` followed by one line per nonzero with `row col value` (0-indexed)