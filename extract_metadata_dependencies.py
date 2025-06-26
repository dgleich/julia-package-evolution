#!/usr/bin/env python3
"""
extract_metadata_dependencies.py

This script extracts package dependencies from the METADATA.jl repository at a specific commit.
METADATA.jl used a different structure than the later General registry.

Updated to extract dependencies from the latest version only (consistent with General registry approach).
"""

import os
import sys
import subprocess
import json
import argparse
from pathlib import Path
import tomllib
from collections import defaultdict

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

def checkout_commit(commit_hash):
    """Checkout a specific commit in the repository."""
    run_git_command(["checkout", commit_hash])

class MetadataPackage:
    """Handler for METADATA.jl package format."""
    
    def __init__(self, package_dir):
        self.package_dir = Path(package_dir)
        self.name = self.package_dir.name
    
    def exists(self):
        """Check if this package exists with appropriate structure."""
        # METADATA.jl structure was more basic - packages usually have a url file and versions dir
        url_file = self.package_dir / "url"
        versions_dir = self.package_dir / "versions"
        return url_file.exists() or versions_dir.exists()
    
    def extract_metadata(self):
        """Extract basic package metadata."""
        url_file = self.package_dir / "url"
        
        # Generate a UUID-like identifier for packages (for compatibility)
        # This is a placeholder; actual UUIDs were introduced later
        uuid = f"metadata-{self.name.lower()}"
        
        metadata = {
            "name": self.name,
            "uuid": uuid
        }
        
        # Add repo URL if available
        if url_file.exists():
            try:
                with open(url_file, "r") as f:
                    metadata["repo"] = f.read().strip()
            except Exception as e:
                print(f"Error reading URL from {url_file}: {e}")
        
        return metadata
    
    def extract_dependencies(self):
        """Extract dependencies for this package from the latest version only."""
        versions_dir = self.package_dir / "versions"
        if not versions_dir.exists() or not versions_dir.is_dir():
            return {}
        
        # Get all versions and find the latest one
        versions = self.extract_versions()
        if not versions:
            return {}
        
        # Find the latest version using proper version comparison
        def version_tuple(v):
            # Clean version string to handle non-standard formats
            # Remove common suffixes like "+0", "+1", "-alpha", etc.
            clean_v = v.split('+')[0].split('-')[0]
            
            # Handle pure alpha versions by returning a very low version
            if clean_v.isalpha() or not any(c.isdigit() for c in clean_v):
                return (0, 0, 0)
                
            # Split by dots and convert to integers, handling any remaining non-digits
            parts = []
            for part in clean_v.split('.'):
                # Extract only the numeric part from each component
                numeric_part = ''.join(c for c in part if c.isdigit())
                parts.append(int(numeric_part) if numeric_part else 0)
            
            # Ensure we have at least 3 parts for consistent comparison
            while len(parts) < 3:
                parts.append(0)
                
            return tuple(parts)
        
        latest_version = max(versions.keys(), key=version_tuple)
        
        # Extract dependencies from the latest version only
        latest_version_dir = versions_dir / latest_version
        requires_file = latest_version_dir / "requires"
        
        if not requires_file.exists():
            return {}
        
        deps = {}
        
        try:
            with open(requires_file, "r") as f:
                requires_content = f.readlines()
            
            # Parse the requires file (simple format, one dependency per line)
            for line in requires_content:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                
                # Extract package name (ignoring version constraints)
                parts = line.split()
                if not parts:
                    continue
                
                dep_name = parts[0]
                if dep_name == "julia":  # Skip julia version requirement
                    continue
                
                # Create a mock UUID (same pattern as in extract_metadata)
                dep_uuid = f"metadata-{dep_name.lower()}"
                
                # Store the dependency
                deps[dep_uuid] = dep_name
        
        except Exception as e:
            print(f"Error reading dependencies from {requires_file}: {e}")
        
        return deps
    
    def extract_versions(self):
        """Extract version information for this package."""
        versions_dir = self.package_dir / "versions"
        if not versions_dir.exists() or not versions_dir.is_dir():
            return {}
        
        versions = {}
        
        # Process each version directory
        for version_dir in versions_dir.iterdir():
            if not version_dir.is_dir():
                continue
            
            version = version_dir.name
            sha_file = version_dir / "sha1"
            
            if sha_file.exists():
                try:
                    with open(sha_file, "r") as f:
                        sha = f.read().strip()
                        versions[version] = {"hash-sha1": sha}
                except Exception as e:
                    print(f"Error reading SHA from {sha_file}: {e}")
        
        return versions
    
    def extract_all(self):
        """Extract all information for this package."""
        return {
            "metadata": self.extract_metadata(),
            "dependencies": self.extract_dependencies(),
            "versions": self.extract_versions(),
            "compatibility": {}  # No formal compatibility in METADATA.jl
        }

def get_all_package_directories(repo_path):
    """Get all package directories in METADATA.jl."""
    packages = []
    
    # In METADATA.jl, packages are directly in the root
    for item in repo_path.iterdir():
        if item.is_dir() and item.name not in [".git", ".github"]:
            packages.append(item)
    
    return packages

def extract_metadata_snapshot(commit_hash):
    """Extract a complete dependency snapshot from METADATA.jl at a specific commit."""
    repo_path = get_repo_path()
    
    # Checkout the specific commit
    print(f"Checking out commit {commit_hash}")
    checkout_commit(commit_hash)
    
    # Get all package directories
    package_dirs = get_all_package_directories(repo_path)
    print(f"Found {len(package_dirs)} potential packages")
    
    snapshot = {
        "commit": commit_hash,
        "source": "metadata",
        "packages": {},
        "dependencies": {}
    }
    
    valid_packages = 0
    for package_dir in package_dirs:
        package_name = package_dir.name
        
        # Create handler
        handler = MetadataPackage(package_dir)
        
        if not handler.exists():
            continue
        
        valid_packages += 1
        
        # Extract all package information
        package_info = handler.extract_all()
        
        snapshot["packages"][package_name] = {
            "metadata": package_info["metadata"],
            "versions": package_info["versions"],
            "compatibility": package_info["compatibility"],
            "format": "metadata",
            "is_jll": False  # No JLL packages in METADATA.jl era
        }
        
        snapshot["dependencies"][package_name] = package_info["dependencies"]
    
    print(f"Found {valid_packages} valid packages")
    return snapshot

def save_snapshot(snapshot, output_path):
    """Save the dependency snapshot to a JSON file."""
    with open(output_path, 'w') as f:
        json.dump(snapshot, f, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Extract dependencies from METADATA.jl at a specific commit")
    parser.add_argument(
        "commit", 
        help="Git commit hash to extract dependencies from"
    )
    parser.add_argument(
        "--output", 
        default=None,
        help="Output file path (default: metadata_dependencies_<commit>.json)"
    )
    
    args = parser.parse_args()
    
    if args.output is None:
        short_commit = args.commit[:8]
        args.output = f"metadata_dependencies_{short_commit}.json"
    
    try:
        # Extract the snapshot
        snapshot = extract_metadata_snapshot(args.commit)
        
        # Save the snapshot
        save_snapshot(snapshot, args.output)
        
        print(f"Extracted dependencies for {len(snapshot['packages'])} packages")
        print(f"Snapshot saved to {args.output}")
        
    except subprocess.CalledProcessError as e:
        print(f"Git command failed: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)
    finally:
        # Return to main branch
        try:
            run_git_command(["checkout", "main"])
        except:
            pass

if __name__ == "__main__":
    main()