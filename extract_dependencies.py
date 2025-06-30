#!/usr/bin/env python3
"""
extract_dependencies.py

This script extracts package dependencies from the Julia Registry at a specific commit.
It handles both early and late registry formats as documented in REGISTRY_CHANGES.md.
"""

import os
import sys
import subprocess
import json
import argparse
from pathlib import Path
import tomllib
from collections import defaultdict
from abc import ABC, abstractmethod
from semantic_version import Version, SimpleSpec


def get_repo_path():
    """Return the path to the Julia Registry repository."""
    script_dir = Path(__file__).parent.absolute()
    return script_dir / "General"


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


class RegistryPackage(ABC):
    """Abstract base class for registry package formats."""
    
    def __init__(self, package_dir):
        self.package_dir = Path(package_dir)
        self.name = self.package_dir.name
    
    @abstractmethod
    def get_metadata_file(self):
        """Return path to metadata file."""
        pass
    
    @abstractmethod
    def get_dependencies_file(self):
        """Return path to dependencies file."""
        pass
    
    @abstractmethod
    def get_versions_file(self):
        """Return path to versions file."""
        pass
    
    @abstractmethod
    def get_compatibility_file(self):
        """Return path to compatibility file."""
        pass
    
    def exists(self):
        """Check if this package format exists in the directory."""
        return self.get_metadata_file().exists()
    
    def extract_metadata(self):
        """Extract basic package metadata."""
        metadata_file = self.get_metadata_file()
        if not metadata_file.exists():
            return None
        
        try:
            with open(metadata_file, "rb") as f:
                metadata = tomllib.load(f)
            return {
                "name": metadata.get("name"),
                "uuid": metadata.get("uuid"),
                "repo": metadata.get("repo")
            }
        except Exception as e:
            print(f"Error reading metadata from {metadata_file}: {e}")
            return None
    
    def extract_dependencies(self):
        """Extract dependencies for this package."""
        deps_file = self.get_dependencies_file()
        if not deps_file.exists():
            return {}
        
        try:
            with open(deps_file, "rb") as f:
                deps_data = tomllib.load(f)
            
            
            # Get the latest version to determine which dependencies apply
            versions = self.extract_versions()
            if not versions:
                # If no versions available, fall back to flattening all dependencies
                all_deps = {}
                for version_range, deps in deps_data.items():
                    if isinstance(deps, dict):
                        all_deps.update(deps)
                return all_deps
            
            # Find the latest version using Version.coerce
            latest_version = max(versions.keys(), key=lambda v: Version.coerce(v))
            
            # Extract dependencies using version range matching
            current_deps = {}
            
            # Check all version ranges to see which apply to the latest version
            for version_range, deps in deps_data.items():
                if not isinstance(deps, dict):
                    continue
                
                if self._version_in_range(latest_version, version_range):
                    current_deps.update(deps)
            
            return current_deps
        except Exception as e:
            print(f"Error reading dependencies from {deps_file}: {e}")
            return {}
    
    def _version_in_range(self, version, version_range):
        """Check if a version falls within a given version range using semantic versioning."""
        try:
            current_version = Version.coerce(version)
            
            # Handle range notation like "0.1-0.6", "0-2", "0.5-2"
            if "-" in version_range:
                start, end = version_range.split("-", 1)
                # Julia ranges are inclusive: "a-b" means ">=a,<=b"
                spec = SimpleSpec(f">={start},<={end}")
                return current_version in spec
            
            # Single version - exact match using SimpleSpec
            else:
                spec = SimpleSpec(f"={version_range}")
                return current_version in spec
                
        except Exception:
            # Fallback to string comparison for malformed versions
            return version == version_range
    
    def extract_versions(self):
        """Extract version information for this package."""
        versions_file = self.get_versions_file()
        if not versions_file.exists():
            return {}
        
        try:
            with open(versions_file, "rb") as f:
                versions_data = tomllib.load(f)
            return versions_data
        except Exception as e:
            print(f"Error reading versions from {versions_file}: {e}")
            return {}
    
    def extract_compatibility(self):
        """Extract compatibility constraints for this package."""
        compat_file = self.get_compatibility_file()
        if not compat_file.exists():
            return {}
        
        try:
            with open(compat_file, "rb") as f:
                compat_data = tomllib.load(f)
            return compat_data
        except Exception as e:
            print(f"Error reading compatibility from {compat_file}: {e}")
            return {}
    
    def extract_all(self):
        """Extract all information for this package."""
        return {
            "metadata": self.extract_metadata(),
            "dependencies": self.extract_dependencies(),
            "versions": self.extract_versions(),
            "compatibility": self.extract_compatibility()
        }


class EarlyRegistryPackage(RegistryPackage):
    """Handler for early registry format (lowercase filenames)."""
    
    def get_metadata_file(self):
        return self.package_dir / "package.toml"
    
    def get_dependencies_file(self):
        return self.package_dir / "dependencies.toml"
    
    def get_versions_file(self):
        return self.package_dir / "versions.toml"
    
    def get_compatibility_file(self):
        return self.package_dir / "compatibility.toml"


class LateRegistryPackage(RegistryPackage):
    """Handler for late registry format (capitalized filenames)."""
    
    def get_metadata_file(self):
        return self.package_dir / "Package.toml"
    
    def get_dependencies_file(self):
        return self.package_dir / "Deps.toml"
    
    def get_versions_file(self):
        return self.package_dir / "Versions.toml"
    
    def get_compatibility_file(self):
        return self.package_dir / "Compat.toml"


def create_package_handler(package_dir):
    """Create appropriate package handler based on detected format."""
    # Try late format first (more common)
    late_handler = LateRegistryPackage(package_dir)
    if late_handler.exists():
        return late_handler, "late"
    
    # Try early format
    early_handler = EarlyRegistryPackage(package_dir)
    if early_handler.exists():
        return early_handler, "early"
    
    return None, "unknown"


def get_packages_from_letter_structure(base_dir):
    """Get packages from A/, B/, C/ letter-based directory structure."""
    packages = []
    for letter_dir in base_dir.iterdir():
        if letter_dir.is_dir() and len(letter_dir.name) == 1 and letter_dir.name.isalpha():
            for package_dir in letter_dir.iterdir():
                if package_dir.is_dir():
                    packages.append(package_dir)
    return packages


def get_all_package_directories(repo_path):
    """Get all package directories in the registry, including jlls."""
    packages = []
    
    # Regular packages organized by first letter (A/, B/, C/, etc.)
    packages.extend(get_packages_from_letter_structure(repo_path))
    
    # JLL packages in the jll directory (also organized by letter)
    jll_dir = repo_path / "jll"
    if jll_dir.exists() and jll_dir.is_dir():
        packages.extend(get_packages_from_letter_structure(jll_dir))
    
    return packages


def extract_registry_snapshot(commit_hash):
    """Extract a complete dependency snapshot from the registry at a specific commit."""
    repo_path = get_repo_path()
    
    # Checkout the specific commit
    print(f"Checking out commit {commit_hash}")
    checkout_commit(commit_hash)
    
    # Get all package directories (including jlls)
    package_dirs = get_all_package_directories(repo_path)
    print(f"Found {len(package_dirs)} packages")
    
    snapshot = {
        "commit": commit_hash,
        "packages": {},
        "dependencies": {},
        "format_stats": {"early": 0, "late": 0, "unknown": 0}
    }
    
    for package_dir in package_dirs:
        package_name = package_dir.name
        
        # Create appropriate handler
        handler, format_type = create_package_handler(package_dir)
        snapshot["format_stats"][format_type] += 1
        
        if handler is None:
            continue
        
        # Extract all package information
        package_info = handler.extract_all()
        
        if package_info["metadata"] is None:
            continue
        
        # Determine if this is a jll package
        is_jll = "jll" in str(package_dir)
        
        snapshot["packages"][package_name] = {
            "metadata": package_info["metadata"],
            "versions": package_info["versions"],
            "compatibility": package_info["compatibility"],
            "format": format_type,
            "is_jll": is_jll
        }
        
        snapshot["dependencies"][package_name] = package_info["dependencies"]
    
    return snapshot


def save_snapshot(snapshot, output_path):
    """Save the dependency snapshot to a JSON file."""
    with open(output_path, 'w') as f:
        json.dump(snapshot, f, indent=2)


def main():
    parser = argparse.ArgumentParser(description="Extract dependencies from Julia Registry at a specific commit")
    parser.add_argument(
        "commit", 
        help="Git commit hash to extract dependencies from"
    )
    parser.add_argument(
        "--output", 
        default=None,
        help="Output file path (default: dependencies_<commit>.json)"
    )
    
    args = parser.parse_args()
    
    if args.output is None:
        short_commit = args.commit[:8]
        args.output = f"dependencies_{short_commit}.json"
    
    try:
        # Extract the snapshot
        snapshot = extract_registry_snapshot(args.commit)
        
        # Save the snapshot
        save_snapshot(snapshot, args.output)
        
        # Count jll vs regular packages
        jll_count = sum(1 for pkg in snapshot["packages"].values() if pkg.get("is_jll", False))
        regular_count = len(snapshot["packages"]) - jll_count
        
        print(f"Extracted dependencies for {len(snapshot['packages'])} packages")
        print(f"  Regular packages: {regular_count}")
        print(f"  JLL packages: {jll_count}")
        print(f"Format distribution: {snapshot['format_stats']}")
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