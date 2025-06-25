#!/usr/bin/env python3
"""
test_all_packages.py

Comprehensive test script to verify dependency extraction against known
dependency lists for multiple important Julia packages.
"""

import sys
from pathlib import Path
from extract_dependencies import *

# Julia standard libraries that should be ignored in dependency matching
# These were bundled with Julia and their inclusion in dependency lists
# changed over time, so we don't want to fail tests based on them
JULIA_STDLIB = {
    "Base64", "CRC32c", "Dates", "DelimitedFiles", "Distributed", "FileWatching",
    "Future", "InteractiveUtils", "Libdl", "LibGit2", "LinearAlgebra", "Logging",
    "Markdown", "Mmap", "Pkg", "Printf", "Profile", "Random", "REPL", "Serialization",
    "SharedArrays", "Sockets", "SparseArrays", "Statistics", "SuiteSparse", "Test",
    "UUIDs", "Unicode", "Downloads"  # Downloads was added in Julia 1.6
}

# Known dependency lists for key packages (latest versions)
KNOWN_DEPENDENCIES = {
    "DifferentialEquations": {
        "BoundaryValueDiffEq",
        "DelayDiffEq", 
        "DiffEqBase",
        "DiffEqCallbacks",
        "DiffEqNoiseProcess",
        "JumpProcesses",
        "LinearAlgebra",
        "LinearSolve",
        "NonlinearSolve",
        "OrdinaryDiffEq",
        "Random",
        "RecursiveArrayTools",
        "Reexport",
        "SciMLBase", 
        "SteadyStateDiffEq",
        "StochasticDiffEq",
        "Sundials"
    },
    
    "Makie": {
        "Animations", "Base64", "CRC32c", "ColorBrewer", "ColorSchemes", "ColorTypes", 
        "Colors", "Contour", "Dates", "DelaunayTriangulation", "Distributions", 
        "DocStringExtensions", "Downloads", "FFMPEG_jll", "FileIO", "FilePaths", 
        "FixedPointNumbers", "Format", "FreeType", "FreeTypeAbstraction", "GeometryBasics", 
        "GridLayoutBase", "ImageBase", "ImageIO", "InteractiveUtils", "Interpolations", 
        "IntervalSets", "InverseFunctions", "Isoband", "KernelDensity", "LaTeXStrings", 
        "LinearAlgebra", "MacroTools", "MakieCore", "Markdown", "MathTeXEngine", 
        "Observables", "OffsetArrays", "PNGFiles", "Packing", "PlotUtils", "PolygonOps", 
        "PrecompileTools", "Printf", "REPL", "Random", "RelocatableFolders", "Scratch", 
        "ShaderAbstractions", "Showoff", "SignedDistanceFields", "SparseArrays", 
        "Statistics", "StatsBase", "StatsFuns", "StructArrays", "TriplotBase", 
        "UnicodeFun", "Unitful"
    },
    
    "MatrixNetworks": {
        "DataStructures",
        "DelimitedFiles", 
        "GenericArpack",  # Should be GenericArpack, NOT Arpack for latest version
        "IterTools",
        "KahanSummation",
        "LinearAlgebra",
        "Printf",
        "Random",
        "SparseArrays",
        "Statistics"
    },
    
    "Triangulate": {
        "DocStringExtensions",
        "Printf", 
        "Triangle_jll"
    },
    
    "ITensors": {
        "Adapt",
        "BitIntegers",
        "ChainRulesCore", 
        "Compat",
        "Dictionaries",
        "DocStringExtensions",
        "Functors",
        "IsApprox",
        "LinearAlgebra",
        "NDTensors",
        "Pkg",
        "Printf",
        "Random",
        "Requires",
        "SerializedElementArrays",
        "SimpleTraits",
        "SparseArrays",
        "StaticArrays",
        "Strided",
        "TimerOutputs",
        "TupleTools",
        "Zeros"
    },
    
    "Plots": {
        "Base64",
        "Contour",
        "Dates",
        "Downloads",
        "FFMPEG",
        "FixedPointNumbers",
        "GR",
        "JLFzf",
        "JSON",
        "LaTeXStrings",
        "Latexify",
        "LinearAlgebra",
        "Measures",
        "NaNMath",
        "Pkg",
        "PlotThemes",
        "PlotUtils",
        "PrecompileTools",
        "Printf",
        "REPL",
        "Random",
        "RecipesBase",
        "RecipesPipeline",
        "Reexport",
        "RelocatableFolders",
        "Requires",
        "Scratch",
        "Showoff",
        "SparseArrays",
        "Statistics",
        "StatsBase",
        "TOML",
        "UUIDs",
        "UnicodeFun",
        "UnitfulLatexify",
        "Unzip"
    }
}

# Known dependency lists for multiple versions of packages
KNOWN_VERSION_DEPENDENCIES = {
    "Plots": {
        "1.40.13": {  # Latest version
            "Base64", "Contour", "Dates", "Downloads", "FFMPEG", "FixedPointNumbers", "GR", "JLFzf",
            "JSON", "LaTeXStrings", "Latexify", "LinearAlgebra", "Measures", "NaNMath", "Pkg",
            "PlotThemes", "PlotUtils", "PrecompileTools", "Printf", "REPL", "Random", "RecipesBase",
            "RecipesPipeline", "Reexport", "RelocatableFolders", "Requires", "Scratch", "Showoff",
            "SparseArrays", "Statistics", "StatsBase", "TOML", "UUIDs", "UnicodeFun", "UnitfulLatexify", "Unzip"
        },
        
        "0.14.0": {  # Historical version
            "RecipesBase", "PlotUtils", "PlotThemes", "Reexport", "StaticArrays", "FixedPointNumbers",
            "Measures", "Showoff", "StatsBase", "JSON", "NaNMath", "Requires", "Contour"
        }
    },
    
    "MatrixNetworks": {
        "1.0.4": {  # Latest with GenericArpack
            "DataStructures", "DelimitedFiles", "GenericArpack", "IterTools", "KahanSummation",
            "LinearAlgebra", "Printf", "Random", "SparseArrays", "Statistics"
        },
        
        "1.0.2": {  # Historical with Arpack (need to verify this list)
            "DataStructures", "DelimitedFiles", "Arpack", "IterTools", "KahanSummation",
            "LinearAlgebra", "Printf", "Random", "SparseArrays", "Statistics"
        }
    },
    
    "DifferentialEquations": {
        "7.16.1": {  # Latest version
            "BoundaryValueDiffEq", "DelayDiffEq", "DiffEqBase", "DiffEqCallbacks", "DiffEqNoiseProcess",
            "JumpProcesses", "LinearAlgebra", "LinearSolve", "NonlinearSolve", "OrdinaryDiffEq",
            "Random", "RecursiveArrayTools", "Reexport", "SciMLBase", "SteadyStateDiffEq",
            "StochasticDiffEq", "Sundials"
        },
        
        "6.0.0": {  # Historical version
            "Reexport", "DiffEqBase", "StochasticDiffEq", "BoundaryValueDiffEq", "OrdinaryDiffEq",
            "Sundials", "DiffEqPDEBase", "DelayDiffEq", "DiffEqCallbacks", "DiffEqMonteCarlo",
            "DiffEqJump", "DiffEqFinancial", "MultiScaleArrays", "DimensionalPlotRecipes",
            "RecursiveArrayTools", "DiffEqNoiseProcess", "SteadyStateDiffEq", "DiffEqPhysics"
        }
    },
    
    "Makie": {
        "0.22.6": {  # Latest version
            "Animations", "Base64", "CRC32c", "ColorBrewer", "ColorSchemes", "ColorTypes", 
            "Colors", "Contour", "Dates", "DelaunayTriangulation", "Distributions", 
            "DocStringExtensions", "Downloads", "FFMPEG_jll", "FileIO", "FilePaths", 
            "FixedPointNumbers", "Format", "FreeType", "FreeTypeAbstraction", "GeometryBasics", 
            "GridLayoutBase", "ImageBase", "ImageIO", "InteractiveUtils", "Interpolations", 
            "IntervalSets", "InverseFunctions", "Isoband", "KernelDensity", "LaTeXStrings", 
            "LinearAlgebra", "MacroTools", "MakieCore", "Markdown", "MathTeXEngine", 
            "Observables", "OffsetArrays", "PNGFiles", "Packing", "PlotUtils", "PolygonOps", 
            "PrecompileTools", "Printf", "REPL", "Random", "RelocatableFolders", "Scratch", 
            "ShaderAbstractions", "Showoff", "SignedDistanceFields", "SparseArrays", 
            "Statistics", "StatsBase", "StatsFuns", "StructArrays", "TriplotBase", 
            "UnicodeFun", "Unitful"
        }
        # Add historical versions when we get the data
    },
    
    "ITensors": {
        "0.9.6": {  # Latest version
            "Adapt", "BitIntegers", "ChainRulesCore", "Compat", "Dictionaries", "DocStringExtensions",
            "Functors", "IsApprox", "LinearAlgebra", "NDTensors", "Pkg", "Printf", "Random", "Requires",
            "SerializedElementArrays", "SimpleTraits", "SparseArrays", "StaticArrays", "Strided",
            "TimerOutputs", "TupleTools", "Zeros"
        }
        # Add historical versions when we get the data
    },
    
    "Triangulate": {
        "2.4.0": {  # Latest version
            "DocStringExtensions", "Printf", "Triangle_jll"
        }
        # Add historical versions when we get the data
    }
    
    # Note: We need historical dependency data for older versions of these packages
    # to add more comprehensive multi-version testing. Currently we only have
    # verified historical data for Plots.jl v0.14.0 and MatrixNetworks.jl v1.0.2
}

def filter_stdlib_from_deps(deps_set):
    """Remove Julia standard libraries from a set of dependencies."""
    return deps_set - JULIA_STDLIB

def compare_dependencies_ignoring_stdlib(expected_deps, extracted_deps):
    """Compare dependency sets while ignoring Julia standard libraries."""
    # Filter out standard libraries from both sets
    expected_filtered = filter_stdlib_from_deps(expected_deps)
    extracted_filtered = filter_stdlib_from_deps(extracted_deps)
    
    # Calculate differences
    missing = expected_filtered - extracted_filtered
    extra = extracted_filtered - expected_filtered
    matching = expected_filtered & extracted_filtered
    
    # Also track which stdlib packages were found/excluded
    expected_stdlib = expected_deps & JULIA_STDLIB
    extracted_stdlib = extracted_deps & JULIA_STDLIB
    
    return {
        'missing': missing,
        'extra': extra, 
        'matching': matching,
        'expected_stdlib': expected_stdlib,
        'extracted_stdlib': extracted_stdlib,
        'expected_filtered': expected_filtered,
        'extracted_filtered': extracted_filtered
    }

def extract_dependencies_for_version(package_name, target_version):
    """Extract dependencies for a specific version of a package."""
    
    repo_path = get_repo_path()
    first_letter = package_name[0].upper()
    package_dir = repo_path / first_letter / package_name
    
    if not package_dir.exists():
        print(f"❌ Package directory not found: {package_dir}")
        return None
    
    handler, format_type = create_package_handler(package_dir)
    
    if handler is None:
        print(f"❌ No handler found for {package_name}")
        return None
    
    try:
        # Get all versions to verify the target version exists
        versions = handler.extract_versions()
        
        if target_version not in versions:
            print(f"❌ Version {target_version} not found in registry")
            available_versions = list(versions.keys())
            print(f"   Available versions: {available_versions[:10]}{'...' if len(available_versions) > 10 else ''}")
            return None
        
        # Use the same logic as extract_dependencies but with target_version
        import tomllib
        
        deps_file = handler.get_dependencies_file()
        with open(deps_file, "rb") as f:
            deps_data = tomllib.load(f)
        
        # Apply dependency extraction logic for target version
        current_deps = {}
        
        # Check for major version base dependencies
        major_version = target_version.split('.')[0]
        if major_version in deps_data and isinstance(deps_data[major_version], dict):
            current_deps.update(deps_data[major_version])
        
        # Also check for "1" which sometimes means general dependencies  
        if "1" in deps_data and isinstance(deps_data["1"], dict):
            current_deps.update(deps_data["1"])
        
        # Find which version-specific ranges apply to the target version
        for version_range, deps in deps_data.items():
            # Skip base major version entries and non-dict entries
            if version_range in [major_version, "1"] or not isinstance(deps, dict):
                continue
                
            if handler._version_in_range(target_version, version_range):
                current_deps.update(deps)
        
        return current_deps, format_type
        
    except Exception as e:
        print(f"❌ Error extracting dependencies for {package_name} v{target_version}: {e}")
        import traceback
        traceback.print_exc()
        return None

def test_package_dependencies(package_name, expected_deps):
    """Test dependency extraction for a specific package against known dependencies."""
    
    print(f"\n{'='*80}")
    print(f"🧪 Testing: {package_name}")
    print(f"{'='*80}")
    
    # Find package directory
    repo_path = get_repo_path()
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
        # Extract package information
        versions = handler.extract_versions()
        extracted_deps_dict = handler.extract_dependencies()
        metadata = handler.extract_metadata()
        
        if not versions:
            print(f"❌ No versions found for {package_name}")
            return False
        
        # Get latest version and extracted dependencies
        latest_version = max(versions.keys(), key=lambda v: tuple(map(int, v.split('.'))))
        extracted_deps = set(extracted_deps_dict.keys())
        
        # Display basic info
        print(f"📦 Package: {metadata.get('name', 'Unknown')}")
        print(f"🔢 Latest version: {latest_version}")
        print(f"📄 Registry format: {format_type}")
        print(f"🆔 UUID: {metadata.get('uuid', 'Unknown')}")
        
        # Compare expected vs extracted, ignoring Julia standard libraries
        comparison = compare_dependencies_ignoring_stdlib(expected_deps, extracted_deps)
        
        print(f"\n📊 Dependency Comparison (excluding Julia stdlib):")
        print(f"✅ Expected non-stdlib dependencies: {len(comparison['expected_filtered'])}")
        print(f"🔍 Extracted non-stdlib dependencies: {len(comparison['extracted_filtered'])}")
        print(f"✅ Matching dependencies: {len(comparison['matching'])}")
        print(f"❌ Missing dependencies: {len(comparison['missing'])}")
        print(f"⚠️  Extra dependencies: {len(comparison['extra'])}")
        
        # Show stdlib info if present
        if comparison['expected_stdlib'] or comparison['extracted_stdlib']:
            print(f"\n📚 Julia Standard Libraries (ignored in comparison):")
            if comparison['expected_stdlib']:
                print(f"  Expected stdlib: {sorted(comparison['expected_stdlib'])}")
            if comparison['extracted_stdlib']:
                print(f"  Extracted stdlib: {sorted(comparison['extracted_stdlib'])}")
        
        # Show details for non-perfect matches
        missing = comparison['missing']
        extra = comparison['extra']
        matching = comparison['matching']
        
        if missing or extra:
            if matching:
                print(f"\n✅ MATCHING DEPENDENCIES ({len(matching)}):")
                for dep in sorted(matching):
                    print(f"  ✓ {dep}")
            
            if missing:
                print(f"\n❌ MISSING DEPENDENCIES ({len(missing)}):")
                for dep in sorted(missing):
                    print(f"  ✗ {dep}")
            
            if extra:
                print(f"\n⚠️  EXTRA DEPENDENCIES ({len(extra)}):")
                for dep in sorted(extra):
                    print(f"  + {dep}")
        
        # Test result (success if no missing/extra non-stdlib dependencies)
        success = len(missing) == 0 and len(extra) == 0
        
        if success:
            print(f"\n🎉 PERFECT MATCH! All {len(comparison['expected_filtered'])} non-stdlib dependencies correctly extracted.")
            if comparison['extracted_stdlib']:
                print(f"   (Plus {len(comparison['extracted_stdlib'])} Julia stdlib dependencies)")
        else:
            print(f"\n❌ MISMATCH DETECTED:")
            if missing:
                print(f"   Missing {len(missing)} expected non-stdlib dependencies")
            if extra:
                print(f"   Found {len(extra)} unexpected non-stdlib dependencies")
        
        return success
        
    except Exception as e:
        print(f"❌ Error testing {package_name}: {e}")
        import traceback
        traceback.print_exc()
        return False

def debug_package_version_ranges(package_name):
    """Debug version ranges for a package if test fails."""
    print(f"\n🔍 Debugging {package_name} version ranges...")
    
    repo_path = get_repo_path()
    first_letter = package_name[0].upper()
    package_dir = repo_path / first_letter / package_name
    handler, _ = create_package_handler(package_dir)
    
    if handler is None:
        print("❌ No handler found")
        return
    
    try:
        import tomllib
        
        # Get version info
        versions = handler.extract_versions()
        latest_version = max(versions.keys(), key=lambda v: tuple(map(int, v.split('.'))))
        
        # Load deps file manually
        deps_file = handler.get_dependencies_file()
        with open(deps_file, "rb") as f:
            deps_data = tomllib.load(f)
        
        print(f"Latest version: {latest_version}")
        print(f"Version ranges in Deps.toml:")
        
        for range_key, deps in deps_data.items():
            if isinstance(deps, dict):
                matches = handler._version_in_range(latest_version, str(range_key))
                dep_count = len(deps)
                print(f"  [{range_key}]: {dep_count} deps, matches {latest_version}: {matches}")
                if matches and dep_count <= 5:  # Only show deps for small lists
                    print(f"    Dependencies: {list(deps.keys())}")
    
    except Exception as e:
        print(f"❌ Debug error: {e}")

def test_package_version(package_name, version, expected_deps):
    """Test dependency extraction for a specific version of a package."""
    
    print(f"\n{'='*80}")
    print(f"🧪 Testing: {package_name} v{version}")
    print(f"{'='*80}")
    
    result = extract_dependencies_for_version(package_name, version)
    if result is None:
        return False
    
    extracted_deps_dict, format_type = result
    extracted_deps = set(extracted_deps_dict.keys())
    
    print(f"📦 Package: {package_name}")
    print(f"🔢 Target version: {version}")
    print(f"📄 Registry format: {format_type}")
    
    # Compare expected vs extracted, ignoring Julia standard libraries
    comparison = compare_dependencies_ignoring_stdlib(expected_deps, extracted_deps)
    
    print(f"\n📊 Dependency Comparison (excluding Julia stdlib):")
    print(f"✅ Expected non-stdlib dependencies: {len(comparison['expected_filtered'])}")
    print(f"🔍 Extracted non-stdlib dependencies: {len(comparison['extracted_filtered'])}")
    print(f"✅ Matching dependencies: {len(comparison['matching'])}")
    print(f"❌ Missing dependencies: {len(comparison['missing'])}")
    print(f"⚠️  Extra dependencies: {len(comparison['extra'])}")
    
    # Show stdlib info if present
    if comparison['expected_stdlib'] or comparison['extracted_stdlib']:
        print(f"\n📚 Julia Standard Libraries (ignored in comparison):")
        if comparison['expected_stdlib']:
            print(f"  Expected stdlib: {sorted(comparison['expected_stdlib'])}")
        if comparison['extracted_stdlib']:
            print(f"  Extracted stdlib: {sorted(comparison['extracted_stdlib'])}")
    
    # Show details for non-perfect matches
    missing = comparison['missing']
    extra = comparison['extra']
    matching = comparison['matching']
    
    if missing or extra:
        if matching:
            print(f"\n✅ MATCHING DEPENDENCIES ({len(matching)}):")
            for dep in sorted(matching):
                print(f"  ✓ {dep}")
        
        if missing:
            print(f"\n❌ MISSING DEPENDENCIES ({len(missing)}):")
            for dep in sorted(missing):
                print(f"  ✗ {dep}")
        
        if extra:
            print(f"\n⚠️  EXTRA DEPENDENCIES ({len(extra)}):")
            for dep in sorted(extra):
                print(f"  + {dep}")
    else:
        print(f"\n🎉 PERFECT MATCH! All {len(comparison['expected_filtered'])} non-stdlib dependencies correctly extracted.")
        if comparison['extracted_stdlib']:
            print(f"   (Plus {len(comparison['extracted_stdlib'])} Julia stdlib dependencies)")
    
    # Test result (success if no missing/extra non-stdlib dependencies)
    success = len(missing) == 0 and len(extra) == 0
    
    return success

def run_version_tests():
    """Run tests on multiple versions of packages."""
    
    if not KNOWN_VERSION_DEPENDENCIES:
        print("ℹ️  No multi-version test data available.")
        return True
    
    print(f"\n{'='*80}")
    print("🧪 Running multi-version dependency extraction tests...")
    print(f"{'='*80}")
    
    all_results = {}
    total_tests = sum(len(versions) for versions in KNOWN_VERSION_DEPENDENCIES.values())
    test_count = 0
    
    for package_name, version_deps in KNOWN_VERSION_DEPENDENCIES.items():
        package_results = {}
        
        for version, expected_deps in version_deps.items():
            test_count += 1
            print(f"\n🔄 Progress: {test_count}/{total_tests}")
            success = test_package_version(package_name, version, expected_deps)
            package_results[version] = success
        
        all_results[package_name] = package_results
    
    # Summary for version tests
    print(f"\n{'='*80}")
    print("📊 MULTI-VERSION TEST SUMMARY")
    print(f"{'='*80}")
    
    total_passed = 0
    total_failed = 0
    
    for package_name, package_results in all_results.items():
        package_passed = sum(package_results.values())
        package_total = len(package_results)
        package_failed = package_total - package_passed
        
        total_passed += package_passed
        total_failed += package_failed
        
        print(f"\n📦 {package_name}:")
        print(f"  ✅ Passed: {package_passed}/{package_total}")
        print(f"  ❌ Failed: {package_failed}/{package_total}")
        
        for version, success in package_results.items():
            status = "✅ PASSED" if success else "❌ FAILED"
            print(f"    v{version}: {status}")
    
    print(f"\n{'='*50}")
    print(f"Overall multi-version results:")
    print(f"✅ Total passed: {total_passed}/{total_tests}")
    print(f"❌ Total failed: {total_failed}/{total_tests}")
    
    if total_failed == 0:
        print(f"🎉 ALL MULTI-VERSION TESTS PASSED!")
    else:
        print(f"⚠️  {total_failed} multi-version test(s) failed.")
    
    return total_failed == 0

def run_all_tests():
    """Run comprehensive tests: latest version tests + multi-version tests."""
    
    print("🧪 Running comprehensive dependency extraction tests...")
    
    # Run latest version tests
    print("\n" + "="*80)
    print("📋 PHASE 1: Testing latest versions of packages")
    print("="*80)
    
    latest_results = {}
    total_packages = len(KNOWN_DEPENDENCIES)
    
    for i, (package_name, expected_deps) in enumerate(KNOWN_DEPENDENCIES.items(), 1):
        print(f"\n🔄 Progress: {i}/{total_packages}")
        success = test_package_dependencies(package_name, expected_deps)
        latest_results[package_name] = success
        
        # If test fails, show debug info
        if not success:
            debug_package_version_ranges(package_name)
    
    # Run multi-version tests
    print("\n" + "="*80)
    print("📋 PHASE 2: Testing multiple versions of packages")
    print("="*80)
    
    version_tests_passed = run_version_tests()
    
    # Combined final summary
    print(f"\n{'='*80}")
    print("📊 COMPREHENSIVE TEST SUMMARY")
    print(f"{'='*80}")
    
    # Latest version results
    latest_passed = sum(latest_results.values())
    latest_failed = len(latest_results) - latest_passed
    
    print(f"\n🔄 PHASE 1 - Latest Version Tests:")
    print(f"✅ Tests passed: {latest_passed}/{total_packages}")
    print(f"❌ Tests failed: {latest_failed}/{total_packages}")
    
    for package_name, success in latest_results.items():
        status = "✅ PASSED" if success else "❌ FAILED"
        print(f"  {package_name} (latest): {status}")
    
    # Multi-version results
    print(f"\n🔄 PHASE 2 - Multi-Version Tests:")
    if KNOWN_VERSION_DEPENDENCIES:
        total_version_tests = sum(len(versions) for versions in KNOWN_VERSION_DEPENDENCIES.values())
        version_status = "✅ PASSED" if version_tests_passed else "❌ FAILED"
        print(f"{version_status} Multi-version tests: {total_version_tests} tests across {len(KNOWN_VERSION_DEPENDENCIES)} packages")
    else:
        print("ℹ️  No multi-version test data available")
        version_tests_passed = True  # Don't fail overall if no version tests
    
    # Overall result
    overall_success = latest_failed == 0 and version_tests_passed
    
    print(f"\n{'='*50}")
    if overall_success:
        print("🎉 ALL TESTS PASSED! Dependency extraction is working perfectly across all versions!")
    else:
        issues = []
        if latest_failed > 0:
            issues.append(f"{latest_failed} latest version test(s) failed")
        if not version_tests_passed:
            issues.append("multi-version tests failed")
        print(f"⚠️  Issues found: {', '.join(issues)}")
    
    print(f"{'='*80}")
    
    return overall_success

if __name__ == "__main__":
    # Run all tests
    success = run_all_tests()
    
    # Exit with appropriate code
    sys.exit(0 if success else 1)