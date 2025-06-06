#!/usr/bin/env python3

import json
import os

def check_deps_in_file(filename):
    """Check how dependencies are structured in a file."""
    with open(filename) as f:
        data = json.load(f)
    
    print(f"\n--- {os.path.basename(filename)} ---")
    
    # Check dependencies
    deps = data.get('dependencies', {})
    print(f"Number of packages with dependencies: {len(deps)}")
    
    # Get a sample
    if deps:
        sample_keys = list(deps.keys())[:3]  # Get first 3 packages with dependencies
        for key in sample_keys:
            sample_deps = deps[key]
            print(f"\nSample dependencies for {key}: {len(sample_deps)} deps")
            for dep_uuid, dep_name in sample_deps.items():
                print(f"  {dep_uuid} -> {dep_name}")
    else:
        print("No dependencies found in the file")
    
    # Check reverse mapping: can we look up packages by UUID?
    packages = data.get('packages', {})
    print(f"\nNumber of packages: {len(packages)}")
    
    # Create UUID to name map
    uuid_to_name = {}
    for pkg_name, pkg_info in packages.items():
        if pkg_info.get('metadata') and pkg_info['metadata'].get('uuid'):
            uuid = pkg_info['metadata']['uuid']
            uuid_to_name[uuid] = pkg_name
    
    print(f"UUID-to-name map size: {len(uuid_to_name)}")
    
    # Check if the UUIDs in dependencies match packages
    if deps and uuid_to_name:
        sample_deps = next(iter(deps.values()))
        print("\nChecking if UUIDs in dependencies match packages:")
        
        found = 0
        for dep_uuid, dep_name in list(sample_deps.items())[:5]:  # Check first 5 deps
            if dep_uuid in uuid_to_name:
                print(f"  ✓ UUID {dep_uuid} found in packages as {uuid_to_name[dep_uuid]}")
                found += 1
            else:
                print(f"  ✗ UUID {dep_uuid} not found in packages")
        
        print(f"Found {found} matches from sample")

# Files to check
files = [
    "dependencies_2019-05.json",  # Recent General file
    "dependencies_2018-03.json"   # Earlier General file
]

for file in files:
    if os.path.exists(file):
        check_deps_in_file(file)
    else:
        print(f"File not found: {file}")