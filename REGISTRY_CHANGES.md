# Julia Registry Structural Changes

This document outlines the major structural changes in the Julia Registry over time, which are important to consider when analyzing package dependencies across different time periods.

## Repository Transition

- **METADATA.jl**: The original Julia package registry (https://github.com/JuliaLang/METADATA.jl)
- **General Registry**: The new Julia package registry (https://github.com/JuliaRegistries/General)

The transition between these repositories began on February 25, 2018, with the commit `fdea9f164d45b616ce775e5506c0bbef70f3bb29` in the General registry. This commit marks the beginning of automatic synchronization from METADATA.jl to the General registry.

## Initial Structure (Aug 2017)

The registry was created in August 2017 with commit `3c5981deae` which generated registry data from METADATA.jl. The initial structure had:

- Packages organized by first letter (A/Atom/, B/Bitcoin/, etc.)
- Each package directory contained:
  - `package.toml`: Basic package metadata (name, UUID, repo)
  - `versions.toml`: Version history with `hash-sha1` identifiers
  - `dependencies.toml`: Dependencies organized by version ranges
  - `compatibility.toml`: Version compatibility constraints

Example from early structure:
```toml
# dependencies.toml
["0.1-0.6"]
CodeTools = "53a63b46-67e4-5edd-8c66-0af0544a99b9"
Hiccup = "9fb69e20-1954-56bb-a84f-559cc56a8ff7"
...
```

## Filename Capitalization Change (2019)

Around 2019, there was a transition to capitalized filenames:

- `package.toml` → `Package.toml`
- `versions.toml` → `Versions.toml`
- `dependencies.toml` → `Deps.toml`
- `compatibility.toml` → `Compat.toml`

## Hash Format Change

The format of version hashes changed:
- Before: `hash-sha1 = "44d22686c94c1f9dac4c6b4a47d55bc2bcaf75aa"`
- After: `git-tree-sha1 = "7c7b82a4e93e2e7c80abd4e7a9ad10dc9a823396"`

This change reflects a shift from SHA-1 hashes to Git tree SHA-1s.

## Dependency Specification Changes

Earlier format in `dependencies.toml`:
```toml
["0.1-0.6"]
CodeTools = "53a63b46-67e4-5edd-8c66-0af0544a99b9"
```

Current format in `Deps.toml`:
```toml
[0]
Base64 = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"
CodeTools = "53a63b46-67e4-5edd-8c66-0af0544a99b9"
...
```

The format for specifying version ranges was simplified, with `[0]` representing all versions starting with 0.

## Compatibility Specification Changes

Earlier format in `compatibility.toml`:
```toml
["0.1-0.4"]
julia = "0.4-0.6"
```

Current format in `Compat.toml`:
```toml
[0]
TreeViews = "0.3"
```

Version constraints are now specified more precisely.

## Implications for Dependency Analysis

When analyzing the Julia package ecosystem's evolution:

1. Account for filename changes when extracting dependencies
2. Parse different version formats appropriately
3. Handle the changing version range specification formats
4. Consider that the hash format changed from `hash-sha1` to `git-tree-sha1`

These structural changes will need to be handled in the code that extracts dependencies from different points in the registry's history.