#!/usr/bin/env python3
"""
index_metadata_commits.py

This script indexes commits in the METADATA.jl repository by time, similar to
index_commits_by_time.py but for the older METADATA.jl repository.
"""

import os
import sys
import subprocess
import json
import datetime
from collections import defaultdict
import argparse
from pathlib import Path

def get_repo_path():
    """Return the path to the METADATA.jl repository."""
    script_dir = Path(__file__).parent.absolute()
    return script_dir / "METADATA"

def run_git_command(cmd, repo_path=None):
    """Run a git command and return the output."""
    if repo_path is None:
        repo_path = get_repo_path()
    
    full_cmd = ["git"] + cmd
    result = subprocess.run(
        full_cmd, 
        cwd=repo_path, 
        capture_output=True, 
        text=True, 
        check=True
    )
    return result.stdout.strip()

def get_all_commits():
    """Get all commits in the repository with their dates."""
    # Format: <commit-hash> <author-date>
    git_log = run_git_command([
        "log", 
        "--format=%H %ad", 
        "--date=iso"
    ])
    
    commits = []
    for line in git_log.splitlines():
        parts = line.split(" ", 1)
        if len(parts) == 2:
            commit_hash, date_str = parts
            # Parse the datetime
            # Clean up the date string format
            date_parts = date_str.split()
            # Format: YYYY-MM-DD HH:MM:SS +ZZZZ
            if len(date_parts) >= 3:
                date_time = " ".join(date_parts[:2])
                date_obj = datetime.datetime.fromisoformat(date_time)
            commits.append({
                "hash": commit_hash,
                "date": date_obj,
                "source": "metadata"  # Mark this as coming from METADATA.jl
            })
    
    return commits

def index_commits_by_day(commits):
    """Group commits by day and select the first commit of each day."""
    days = defaultdict(list)
    
    # Group commits by day
    for commit in commits:
        day_key = commit["date"].strftime("%Y-%m-%d")
        days[day_key].append(commit)
    
    # Sort commits within each day and select the first one
    first_commits_by_day = {}
    for day, day_commits in days.items():
        # Sort by datetime (earliest first)
        day_commits.sort(key=lambda x: x["date"])
        first_commit = day_commits[0]
        
        first_commits_by_day[day] = {
            "hash": first_commit["hash"],
            "datetime": first_commit["date"].isoformat(),
            "source": "metadata"  # Mark this as coming from METADATA.jl
        }
    
    return first_commits_by_day

def index_commits_by_month(commits):
    """Group commits by month and select the first commit of each month."""
    months = defaultdict(list)
    
    # Group commits by month
    for commit in commits:
        month_key = commit["date"].strftime("%Y-%m")
        months[month_key].append(commit)
    
    # Sort commits within each month and select the first one
    first_commits_by_month = {}
    for month, month_commits in months.items():
        # Sort by datetime (earliest first)
        month_commits.sort(key=lambda x: x["date"])
        first_commit = month_commits[0]
        
        first_commits_by_month[month] = {
            "hash": first_commit["hash"],
            "datetime": first_commit["date"].isoformat(),
            "source": "metadata"  # Mark this as coming from METADATA.jl
        }
    
    return first_commits_by_month

def save_index(index, output_path):
    """Save the index to a JSON file."""
    with open(output_path, 'w') as f:
        json.dump(index, f, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Index commits in the METADATA.jl repository by time")
    parser.add_argument(
        "--granularity", 
        choices=["day", "month"], 
        default="day",
        help="Time granularity for indexing (default: day)"
    )
    parser.add_argument(
        "--output", 
        default=None,
        help="Output file path (default: metadata_commits_by_<granularity>.json)"
    )
    
    args = parser.parse_args()
    
    if args.output is None:
        args.output = f"metadata_commits_by_{args.granularity}.json"
    
    # Get all commits
    print(f"Fetching all commits from METADATA.jl repository...")
    all_commits = get_all_commits()
    print(f"Found {len(all_commits)} commits")
    
    # Index commits by the specified granularity
    print(f"Indexing commits by {args.granularity}...")
    if args.granularity == "day":
        index = index_commits_by_day(all_commits)
    elif args.granularity == "month":
        index = index_commits_by_month(all_commits)
    
    print(f"Found {len(index)} unique {args.granularity}s")
    
    # Save the index
    save_index(index, args.output)
    print(f"Index saved to {args.output}")

if __name__ == "__main__":
    main()