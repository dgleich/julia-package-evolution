# Temporal Julia Package Analysis

This project aims to build and analyze the temporal evolution of the Julia package dependency graph over time. By leveraging the historical data in the Julia Registry, we can understand how the package ecosystem has evolved.

## Project Goals

1. Track package dependencies over time using the JuliaRegistries/General git history
2. Build temporal adjacency structures to represent changing package dependencies
3. Analyze the evolution of the Julia package ecosystem
4. Identify important packages and their relationships over time

## Components

- `index_commits_by_time.py`: Python script to index commits by time (daily, potentially hourly/monthly)
- Julia code for building and analyzing the temporal adjacency structures

## How it works

The project uses a combination of Python (for git operations and initial data extraction) and Julia (for dependency analysis and visualization). We leverage the fact that the Julia Registry is stored in git, allowing us to reconstruct the state of package dependencies at any point in time.

## Requirements

- Python 3.x
- Julia 1.x
- Git