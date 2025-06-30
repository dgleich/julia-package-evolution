#!/usr/bin/env python3
"""
test_all_packages.py

Comprehensive test script to verify dependency extraction against known
dependency lists for specific versions of important Julia packages.
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

# Known dependency lists for specific versions of packages
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
        
        "1.0.2": {  # Historical with Arpack
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
        "0.22.4": {  # Latest version
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
    },
    
    "ITensors": {
        "0.9.5": {  # Latest version
            "Adapt", "BitIntegers", "ChainRulesCore", "Compat", "Dictionaries", "DocStringExtensions",
            "Functors", "IsApprox", "LinearAlgebra", "NDTensors", "Pkg", "Printf", "Random", "Requires",
            "SerializedElementArrays", "SimpleTraits", "SparseArrays", "StaticArrays", "Strided",
            "TimerOutputs", "TupleTools", "Zeros"
        }
    },
    
    "Triangulate": {
        "2.4.0": {  # Latest version
            "DocStringExtensions", "Printf", "Triangle_jll"
        }
    },
    
    "LightLearn": {
        "3.0.0": {  # Latest version - tests version parsing with yanked alpha versions
            "Cairo", "ColorTypes", "CommonMark", "Downloads", "Gtk", "JSON", 
            "PNGFiles", "Pkg", "Scratch", "TOML", "ZipFile"
        }
    },
    
    "ACME": {
        "0.6.2": {  # Test version to verify transition period dependency extraction (from 2018-03)
            "Compat", "DataStructures", "IterTools", "ProgressMeter"
        },
        "0.7.5": {  # Current registry version with same dependencies
            "Compat", "DataStructures", "IterTools", "ProgressMeter"
        }
    }
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
        print(f"WARNING: Package directory not found: {package_dir}")
        return None
    
    handler, format_type = create_package_handler(package_dir)
    
    if handler is None:
        print(f"WARNING: No handler found for {package_name}")
        return None
    
    try:
        # Get all versions to verify the target version exists
        versions = handler.extract_versions()
        
        if target_version not in versions:
            print(f"WARNING: Version {target_version} not found in registry")
            available_versions = list(versions.keys())
            print(f"Available versions: {available_versions[:10]}{'...' if len(available_versions) > 10 else ''}")
            return None
        
        # Use the same logic as extract_dependencies but with target_version
        import tomllib
        
        deps_file = handler.get_dependencies_file()
        with open(deps_file, "rb") as f:
            deps_data = tomllib.load(f)
        
        # Extract dependencies using version range matching
        current_deps = {}
        
        # Check all version ranges to see which apply to the target version
        for version_range, deps in deps_data.items():
            if not isinstance(deps, dict):
                continue
                
            if handler._version_in_range(target_version, version_range):
                current_deps.update(deps)
        
        return current_deps, format_type
        
    except Exception as e:
        print(f"ERROR: Failed to extract dependencies for {package_name} v{target_version}: {e}")
        import traceback
        traceback.print_exc()
        return None

def debug_package_version(package_name, version):
    """Debug dependency extraction for a specific version of a package."""
    
    print(f"\n{'='*80}")
    print(f"DEBUG: {package_name} v{version}")
    print(f"{'='*80}")
    
    repo_path = get_repo_path()
    first_letter = package_name[0].upper()
    package_dir = repo_path / first_letter / package_name
    
    print(f"Package directory: {package_dir}")
    print(f"Directory exists: {package_dir.exists()}")
    
    if not package_dir.exists():
        print(f"ERROR: Package directory not found")
        return
    
    # List package files
    print(f"Package files: {list(package_dir.iterdir())}")
    
    handler, format_type = create_package_handler(package_dir)
    print(f"Handler type: {type(handler).__name__ if handler else None}")
    print(f"Format type: {format_type}")
    
    if handler is None:
        print(f"ERROR: No handler found")
        return
    
    # Show all versions
    versions = handler.extract_versions()
    print(f"All versions: {list(versions.keys())}")
    print(f"Target version {version} exists: {version in versions}")
    
    if version not in versions:
        print(f"ERROR: Version {version} not found")
        return
    
    # Show raw dependency file content
    deps_file = handler.get_dependencies_file()
    print(f"\nDependency file: {deps_file}")
    print(f"Dependency file exists: {deps_file.exists()}")
    
    if deps_file.exists():
        try:
            with open(deps_file, "r") as f:
                deps_content = f.read()
            print(f"Raw Deps.toml content:")
            print(deps_content)
        except Exception as e:
            print(f"Error reading deps file: {e}")
    
    # Extract dependencies for the specific version requested
    try:
        result = extract_dependencies_for_version(package_name, version)
        if result:
            version_deps_dict, _ = result
            print(f"\nExtracted dependencies for {version}: {version_deps_dict}")
        else:
            print(f"\nNo version-specific extraction available for {version}")
            
    except Exception as e:
        print(f"Error extracting dependencies: {e}")
        import traceback
        traceback.print_exc()

def test_package_version(package_name, version, expected_deps):
    """Test dependency extraction for a specific version of a package."""
    
    print(f"\n{'='*80}")
    print(f"Testing: {package_name} v{version}")
    print(f"{'='*80}")
    
    result = extract_dependencies_for_version(package_name, version)
    if result is None:
        return None  # Return None for skipped tests
    
    extracted_deps_dict, format_type = result
    extracted_deps = set(extracted_deps_dict.keys())
    
    print(f"Package: {package_name}")
    print(f"Target version: {version}")
    print(f"Registry format: {format_type}")
    
    # Compare expected vs extracted, ignoring Julia standard libraries
    comparison = compare_dependencies_ignoring_stdlib(expected_deps, extracted_deps)
    
    print(f"\nDependency Comparison (excluding Julia stdlib):")
    print(f"Expected non-stdlib dependencies: {len(comparison['expected_filtered'])}")
    print(f"Extracted non-stdlib dependencies: {len(comparison['extracted_filtered'])}")
    print(f"Matching dependencies: {len(comparison['matching'])}")
    print(f"Missing dependencies: {len(comparison['missing'])}")
    print(f"Extra dependencies: {len(comparison['extra'])}")
    
    # Show stdlib info if present
    if comparison['expected_stdlib'] or comparison['extracted_stdlib']:
        print(f"\nJulia Standard Libraries (ignored in comparison):")
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
            print(f"\nMATCHING DEPENDENCIES ({len(matching)}):")
            for dep in sorted(matching):
                print(f"  + {dep}")
        
        if missing:
            print(f"\nMISSING DEPENDENCIES ({len(missing)}):")
            for dep in sorted(missing):
                print(f"  - {dep}")
        
        if extra:
            print(f"\nEXTRA DEPENDENCIES ({len(extra)}):")
            for dep in sorted(extra):
                print(f"  + {dep}")
    else:
        print(f"\nPERFECT MATCH! All {len(comparison['expected_filtered'])} non-stdlib dependencies correctly extracted.")
        if comparison['extracted_stdlib']:
            print(f"(Plus {len(comparison['extracted_stdlib'])} Julia stdlib dependencies)")
    
    # Test result (success if no missing/extra non-stdlib dependencies)
    success = len(missing) == 0 and len(extra) == 0
    
    return success

def run_all_tests():
    """Run tests for all package versions."""
    
    print("Running dependency extraction tests for specific package versions...")
    
    all_results = {}
    total_tests = sum(len(versions) for versions in KNOWN_VERSION_DEPENDENCIES.values())
    test_count = 0
    
    for package_name, version_deps in KNOWN_VERSION_DEPENDENCIES.items():
        package_results = {}
        
        for version, expected_deps in version_deps.items():
            test_count += 1
            print(f"\nProgress: {test_count}/{total_tests}")
            success = test_package_version(package_name, version, expected_deps)
            package_results[version] = success
        
        all_results[package_name] = package_results
    
    # Summary
    print(f"\n{'='*80}")
    print("TEST SUMMARY")
    print(f"{'='*80}")
    
    total_passed = 0
    total_failed = 0
    
    for package_name, package_results in all_results.items():
        # Count actual results, excluding None (skipped)
        actual_results = {v: r for v, r in package_results.items() if r is not None}
        skipped_results = {v: r for v, r in package_results.items() if r is None}
        
        package_passed = sum(actual_results.values())
        package_total = len(actual_results)
        package_failed = package_total - package_passed
        package_skipped = len(skipped_results)
        
        total_passed += package_passed
        total_failed += package_failed
        
        print(f"\n{package_name}:")
        if package_total > 0:
            print(f"  Passed: {package_passed}/{package_total}")
            print(f"  Failed: {package_failed}/{package_total}")
        if package_skipped > 0:
            print(f"  Skipped: {package_skipped}")
        
        for version, success in package_results.items():
            if success is None:
                status = "SKIPPED"
            elif success:
                status = "PASSED"
            else:
                status = "FAILED"
            print(f"    v{version}: {status}")
    
    # Calculate total actual tests (excluding skipped)
    total_actual = total_passed + total_failed
    total_skipped = total_tests - total_actual
    
    print(f"\n{'='*50}")
    print(f"Overall results:")
    print(f"Total passed: {total_passed}/{total_actual}")
    print(f"Total failed: {total_failed}/{total_actual}")
    if total_skipped > 0:
        print(f"Total skipped: {total_skipped}")
    
    if total_failed == 0 and total_actual > 0:
        print(f"ALL TESTS PASSED!")
    elif total_failed > 0:
        print(f"WARNING: {total_failed} test(s) failed.")
    
    return total_failed == 0

if __name__ == "__main__":
    # Check for debug mode
    if len(sys.argv) == 3 and sys.argv[1] == "--debug":
        # Debug mode: python test_all_packages.py --debug PackageName version
        package_name = sys.argv[2]
        
        # If version not provided, look for the package in our test cases
        if package_name in KNOWN_VERSION_DEPENDENCIES:
            versions = list(KNOWN_VERSION_DEPENDENCIES[package_name].keys())
            print(f"Available test versions for {package_name}: {versions}")
            print("Usage: python test_all_packages.py --debug PackageName version")
            sys.exit(1)
        else:
            print(f"Package {package_name} not found in test cases")
            sys.exit(1)
    elif len(sys.argv) == 4 and sys.argv[1] == "--debug":
        # Debug mode with specific version
        package_name = sys.argv[2]
        version = sys.argv[3]
        debug_package_version(package_name, version)
        sys.exit(0)
    else:
        # Run all tests
        success = run_all_tests()
        
        # Exit with appropriate code
        sys.exit(0 if success else 1)