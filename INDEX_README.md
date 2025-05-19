# Julia Registry Time Indexing

The `index_commits_by_time.py` script creates an index mapping time periods to the first commit from that period in the Julia Registry.

## Usage

```bash
# Activate the virtual environment
source .venv/bin/activate

# Index by day (default)
python index_commits_by_time.py 

# Index by month
python index_commits_by_time.py --granularity month

# Index by hour
python index_commits_by_time.py --granularity hour

# Specify custom output file
python index_commits_by_time.py --output custom_output.json
```

## Output Format

The script produces a JSON file with the following structure:

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

## Results

- When run with monthly granularity, the script found **92 unique months** of Julia Registry history.
- When run with daily granularity, the script found **2636 unique days** with commits.

These commits can be used to analyze the evolution of the Julia package ecosystem over time by:
1. Checking out each commit
2. Extracting package dependency information
3. Building temporal adjacency structures