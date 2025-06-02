#!/usr/bin/env python3
"""
Build dependency files for each month from the commits_by_month.json index.
"""

import os
import json
import subprocess
import sys
import time
from pathlib import Path
import datetime

def load_monthly_commits(index_file):
    """Load the monthly commits from the index file."""
    with open(index_file, 'r') as f:
        data = json.load(f)
    return data

def extract_dependencies(commit_hash, output_file, month, current_index, total_months):
    """Extract dependencies for a specific commit."""
    # Create a progress indicator
    progress = f"[{current_index}/{total_months}] {month}"
    
    cmd = ["python3", "extract_dependencies.py", commit_hash, "--output", output_file]
    try:
        start_time = time.time()
        print(f"\n{progress}: Starting extraction for commit {commit_hash[:8]}")
        
        # Run the extraction process
        result = subprocess.run(
            cmd,
            check=True,
            capture_output=True,
            text=True
        )
        
        duration = time.time() - start_time
        print(f"{progress}: Successfully extracted dependencies in {duration:.1f} seconds")
        
        # Check the file size
        file_size_mb = os.path.getsize(output_file) / (1024 * 1024)
        print(f"{progress}: Output file size: {file_size_mb:.2f} MB")
        
        return True
    except subprocess.CalledProcessError as e:
        print(f"{progress}: Error extracting dependencies: {e}")
        print(f"STDOUT: {e.stdout}")
        print(f"STDERR: {e.stderr}")
        return False

def main():
    # Print start time
    start_time = time.time()
    print(f"Starting dependency extraction at {datetime.datetime.now()}")
    
    index_file = "commits_by_month.json"
    monthly_commits = load_monthly_commits(index_file)
    
    # Sort by date to process older commits first (which should be faster)
    months_sorted = sorted(monthly_commits.keys())
    total_months = len(months_sorted)
    
    print(f"Found {total_months} months to process")
    print(f"Earliest: {months_sorted[0]}, Latest: {months_sorted[-1]}")
    
    # Track completion statistics
    completed = []
    skipped = []
    failed = []
    
    # Process each month sequentially
    for i, month in enumerate(months_sorted, 1):
        commit_data = monthly_commits[month]
        commit_hash = commit_data["hash"]
        output_file = f"dependencies_{month}.json"
        
        # Skip if the file already exists
        if os.path.exists(output_file):
            print(f"[{i}/{total_months}] {month}: Skipping, file already exists ({os.path.getsize(output_file)/(1024*1024):.2f} MB)")
            skipped.append(month)
            continue
        
        # Extract dependencies for this month
        success = extract_dependencies(commit_hash, output_file, month, i, total_months)
        if success:
            completed.append(month)
        else:
            print(f"[{i}/{total_months}] {month}: Failed to extract dependencies")
            failed.append(month)
            # Continue with the next month even if this one fails
    
    # Print summary
    end_time = time.time()
    total_duration = end_time - start_time
    hours, remainder = divmod(total_duration, 3600)
    minutes, seconds = divmod(remainder, 60)
    
    print("\n=== Extraction Summary ===")
    print(f"Total runtime: {int(hours)}h {int(minutes)}m {int(seconds)}s")
    print(f"Completed: {len(completed)}/{total_months}")
    print(f"Skipped (already existed): {len(skipped)}/{total_months}")
    print(f"Failed: {len(failed)}/{total_months}")
    
    if failed:
        print("\nFailed months:")
        for month in failed:
            print(f"  {month}")

if __name__ == "__main__":
    main()