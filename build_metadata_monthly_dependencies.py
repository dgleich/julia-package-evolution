#!/usr/bin/env python3
"""
build_metadata_monthly_dependencies.py

This script builds monthly dependency snapshots from the METADATA.jl repository
using the commit indices created by index_metadata_commits.py.
"""

import os
import sys
import json
import subprocess
import time
import datetime
from pathlib import Path

def load_json(file_path):
    """Load a JSON file."""
    with open(file_path, 'r') as f:
        return json.load(f)

def run_command(command):
    """Run a shell command and return the output."""
    result = subprocess.run(
        command,
        shell=True,
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        print(f"Command failed: {command}")
        print(f"Error: {result.stderr}")
        return None
    return result.stdout.strip()

def extract_dependencies_for_month(month, commit_hash):
    """Extract dependencies for a specific month."""
    output_file = f"metadata_dependencies_{month}.json"
    
    # Skip if the file already exists
    if os.path.exists(output_file):
        file_size = os.path.getsize(output_file) / (1024 * 1024)  # Size in MB
        print(f"[{month}] Skipping, file already exists ({file_size:.2f} MB)")
        return True
    
    print(f"[{month}] Starting extraction for commit {commit_hash}")
    start_time = time.time()
    
    # Run the extraction script
    command = f"python extract_metadata_dependencies.py {commit_hash} --output {output_file}"
    output = run_command(command)
    
    if output is None:
        print(f"[{month}] Failed to extract dependencies")
        return False
    
    end_time = time.time()
    duration = end_time - start_time
    
    # Check if the file was created successfully
    if os.path.exists(output_file):
        file_size = os.path.getsize(output_file) / (1024 * 1024)  # Size in MB
        print(f"[{month}] Successfully extracted dependencies in {duration:.1f} seconds")
        print(f"[{month}] Output file size: {file_size:.2f} MB")
        return True
    else:
        print(f"[{month}] Failed to create output file")
        return False

def main():
    # Check if commits_by_month.json exists
    if not os.path.exists("metadata_commits_by_month.json"):
        print("Error: metadata_commits_by_month.json not found")
        print("Please run index_metadata_commits.py first")
        sys.exit(1)
    
    # Load monthly commits
    monthly_commits = load_json("metadata_commits_by_month.json")
    
    # Process each month
    months = sorted(monthly_commits.keys())
    print(f"Found {len(months)} months to process")
    print(f"Earliest: {months[0]}, Latest: {months[-1]}")
    
    with open("metadata_dependency_extraction.log", "w") as log_file:
        log_file.write(f"Starting dependency extraction at {datetime.datetime.now()}\n")
        log_file.write(f"Found {len(months)} months to process\n")
        log_file.write(f"Earliest: {months[0]}, Latest: {months[-1]}\n")
    
    completed = 0
    skipped = 0
    failed = 0
    
    start_time = time.time()
    
    for i, month in enumerate(months):
        commit_info = monthly_commits[month]
        commit_hash = commit_info["hash"]
        
        print(f"[{i+1}/{len(months)}] {month}: ", end="", flush=True)
        
        if os.path.exists(f"metadata_dependencies_{month}.json"):
            print(f"Skipping, file already exists ({os.path.getsize(f'metadata_dependencies_{month}.json') / (1024 * 1024):.2f} MB)")
            skipped += 1
            continue
        
        success = extract_dependencies_for_month(month, commit_hash)
        
        if success:
            completed += 1
        else:
            failed += 1
    
    end_time = time.time()
    total_runtime = end_time - start_time
    
    # Format as hours and minutes
    hours, remainder = divmod(total_runtime, 3600)
    minutes, seconds = divmod(remainder, 60)
    
    print("\n=== Extraction Summary ===")
    print(f"Total runtime: {int(hours)}h {int(minutes)}m {int(seconds)}s")
    print(f"Completed: {completed}/{len(months)}")
    print(f"Skipped (already existed): {skipped}/{len(months)}")
    print(f"Failed: {failed}/{len(months)}")
    
    with open("metadata_dependency_extraction.log", "a") as log_file:
        log_file.write("\n=== Extraction Summary ===\n")
        log_file.write(f"Total runtime: {int(hours)}h {int(minutes)}m {int(seconds)}s\n")
        log_file.write(f"Completed: {completed}/{len(months)}\n")
        log_file.write(f"Skipped (already existed): {skipped}/{len(months)}\n")
        log_file.write(f"Failed: {failed}/{len(months)}\n")

if __name__ == "__main__":
    main()