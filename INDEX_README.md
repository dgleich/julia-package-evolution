# Julia Registry Time Indexing

This project includes scripts for indexing commits from both the original METADATA.jl and current General registries, allowing for a comprehensive temporal analysis of the Julia package ecosystem from 2012 to present.

## Indexing Scripts

### General Registry Indexing

The `index_commits_by_time.py` script creates an index mapping time periods to the first commit from each period in the General registry.

```bash
# Activate the virtual environment
source .venv/bin/activate

# Index by month (recommended)
python index_commits_by_time.py --granularity month

# Index by day (for more detailed analysis)
python index_commits_by_time.py 

# Specify custom output file
python index_commits_by_time.py --output custom_output.json
```

### METADATA.jl Registry Indexing

The `index_metadata_commits.py` script performs similar indexing for the METADATA.jl registry, extending our coverage back to 2012.

```bash
# Index METADATA.jl by month
python index_metadata_commits.py
```

## Output Format

Both scripts produce JSON files with the following structure:

```json
{
  "2025-05-01": {
    "hash": "6b69cc8985c95a057d5bebb947ea5d7fffcaef29",
    "datetime": "2025-05-01T00:17:56"
  },
  ...
}
```

Where:
- The key is the time period (day, month, or hour depending on granularity)
- `hash` is the commit hash of the first commit in that period
- `datetime` is the ISO-formatted timestamp of that commit

## Registry Transition

The Julia package ecosystem underwent a transition from METADATA.jl to the General registry on February 25, 2018 (commit `fdea9f164d45b616ce775e5506c0bbef70f3bb29`). Our analysis spans both registries:

- **METADATA.jl** (Aug 2012 - Feb 2018): The original Julia package registry
- **General Registry** (Feb 2018 - Present): The current Julia package registry

## Results

- From the General registry, we found **92 unique months** of history
- From METADATA.jl, we extended our coverage back to 2012, adding **65 more months**
- In total, we have **152 unique months** spanning August 2012 to May 2025

## Comprehensive Timeline

These indexed commits allow us to analyze the evolution of the Julia package ecosystem over its entire history by:
1. Checking out commits from the appropriate registry based on the date
2. Extracting package dependency information with format-specific parsers
3. Building temporal adjacency structures with a consistent package index across both registries
4. Analyzing the growth and evolution of package dependencies over time