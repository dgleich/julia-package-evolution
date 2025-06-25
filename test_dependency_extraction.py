#!/usr/bin/env python3
"""
test_dependency_extraction.py

Test cases for the dependency extraction logic to verify correctness
against known packages and their expected dependencies.
"""

import sys
import json
from pathlib import Path
from extract_dependencies import *

def test_package_dependencies(package_name, expected_deps=None, show_details=False):
    """Test dependency extraction for a specific package."""
    print(f"\n{'='*60}")
    print(f"Testing: {package_name}")
    print(f"{'='*60}")
    
    repo_path = get_repo_path()
    
    # Find package directory - check first letter
    first_letter = package_name[0].upper()
    package_dir = repo_path / first_letter / package_name
    
    if not package_dir.exists():
        print(f"❌ Package directory not found: {package_dir}")
        return False
    
    handler, format_type = create_package_handler(package_dir)
    
    if handler is None:
        print(f"❌ No handler found for {package_name}")
        return False
    
    try:
        # Extract information
        versions = handler.extract_versions()
        deps = handler.extract_dependencies()
        metadata = handler.extract_metadata()
        
        if not versions:
            print(f"❌ No versions found for {package_name}")
            return False
        
        # Get latest version
        latest_version = max(versions.keys(), key=lambda v: tuple(map(int, v.split('.'))))
        
        print(f"📦 Package: {metadata.get('name', 'Unknown')}")
        print(f"🔢 Latest version: {latest_version}")
        print(f"📄 Registry format: {format_type}")
        print(f"🔗 Dependencies found: {len(deps)}")
        
        if show_details:
            print(f"\n📋 All dependencies:")
            for dep in sorted(deps.keys()):
                print(f"  - {dep}")
        
        # If expected dependencies provided, compare
        if expected_deps is not None:
            extracted_deps = set(deps.keys())
            expected_set = set(expected_deps)
            
            missing = expected_set - extracted_deps
            extra = extracted_deps - expected_set
            
            print(f"\n✅ Expected: {len(expected_set)}")
            print(f"✅ Extracted: {len(extracted_deps)}")
            
            if missing:
                print(f"❌ Missing dependencies: {sorted(missing)}")
            if extra:
                print(f"⚠️  Extra dependencies: {sorted(extra)}")
            
            if not missing and not extra:
                print(f"🎉 Perfect match! All {len(expected_set)} dependencies correct.")
                return True
            else:
                print(f"❌ Mismatch found")
                return False
        else:
            print(f"ℹ️  No expected dependencies provided - showing extracted deps")
            return True
            
    except Exception as e:
        print(f"❌ Error testing {package_name}: {e}")
        return False

def test_version_range_logic():
    """Test the version range matching logic with known cases."""
    print(f"\n{'='*60}")
    print(f"Testing: Version Range Logic")
    print(f"{'='*60}")
    
    # Create a dummy handler to test version range logic
    repo_path = get_repo_path()
    package_dir = repo_path / 'M' / 'Makie'  # Use any existing package
    handler, _ = create_package_handler(package_dir)
    
    if handler is None:
        print("❌ Could not create handler for testing")
        return False
    
    test_cases = [
        # (version, range, expected_result, description)
        ("1.0.4", "1-1.0.2", False, "MatrixNetworks: 1.0.4 should NOT match 1-1.0.2"),
        ("1.0.4", "1.0.3-1", True, "MatrixNetworks: 1.0.4 should match 1.0.3-1"),
        ("1.0.2", "1-1.0.2", True, "MatrixNetworks: 1.0.2 should match 1-1.0.2"),
        ("0.22.6", "0", True, "Makie: 0.22.6 should match base 0"),
        ("0.22.6", "0.22-0", True, "Makie: 0.22.6 should match 0.22-0"),
        ("0.22.6", "0.13-0", True, "Makie: 0.22.6 should match 0.13-0"),
        ("0.22.6", "0-0.12", False, "Makie: 0.22.6 should NOT match 0-0.12"),
        ("2.4.0", "0-2", True, "Triangulate: 2.4.0 should match 0-2"),
        ("2.4.0", "0.5-2", True, "Triangulate: 2.4.0 should match 0.5-2"),
        ("2.4.0", "0-2.2", False, "Triangulate: 2.4.0 should NOT match 0-2.2"),
        ("3.0.0", "0-2", False, "Triangulate: 3.0.0 should NOT match 0-2"),
    ]
    
    all_passed = True
    for version, range_str, expected, description in test_cases:
        result = handler._version_in_range(version, range_str)
        status = "✅" if result == expected else "❌"
        print(f"{status} {description}: {result}")
        if result != expected:
            all_passed = False
    
    return all_passed

def run_package_tests():
    """Run tests on several important packages."""
    print("🧪 Running dependency extraction tests...")
    
    # Test version range logic first
    version_test_passed = test_version_range_logic()
    
    # Test packages - we'll collect their dependencies and you can verify
    packages_to_test = [
        "DifferentialEquations",
        "Plots", 
        "ITensors",
        "Makie",
        "MatrixNetworks", 
        "Triangulate"
    ]
    
    results = {}
    
    for package in packages_to_test:
        print(f"\n" + "="*80)
        success = test_package_dependencies(package, show_details=True)
        results[package] = success
    
    # Summary
    print(f"\n{'='*80}")
    print("📊 TEST SUMMARY")
    print(f"{'='*80}")
    print(f"Version range logic: {'✅ PASSED' if version_test_passed else '❌ FAILED'}")
    
    for package, success in results.items():
        status = "✅ EXTRACTED" if success else "❌ FAILED"
        print(f"{package}: {status}")
    
    return results

if __name__ == "__main__":
    results = run_package_tests()