# Julia Package Dependency Networks: Temporal Adjacency Matrices

This dataset contains temporal adjacency matrices representing Julia package dependency networks from August 2012 to May 2025.

## Dataset Overview

- **Time Period**: 2012-08 to 2025-05 (152 monthly snapshots)
- **Package Count**: 12,884 unique Julia packages
- **Format**: Sparse Matrix Format (SMAT)
- **Source Registries**: METADATA.jl (2012-2018) and General Registry (2018-2025)

## Files Description

### Matrix Files
- `adj_YYYY-MM.smat`: Sparse adjacency matrix for each month
- Matrices are 12,884 × 12,884 with consistent package indexing across all time periods
- Entry (i,j) = 1 indicates package i depends on package j

### Labels File
- `package_labels.txt`: Package names and first appearance dates
- Format: `PackageName,YYYY-MM` (one per line)
- Line number corresponds to package index in matrices

## Data Format

### SMAT Format
The Sparse Matrix Format (SMAT) is a text-based format for sparse matrices:
```
%%MatrixMarket matrix coordinate integer general
%% Generated from Julia package dependencies
rows cols nnz
row1 col1 value1
row2 col2 value2
...
```

### Package Indexing
- Packages are indexed 1-12,884 consistently across all time periods
- Index assignment preserves temporal ordering of first appearances
- Package names and first appearance dates are in `package_labels.txt`

## Data Generation

### Dual Registry System
The dataset combines two Julia package registries:

1. **METADATA.jl Registry (2012-2018)**
   - Original Julia registry with custom metadata format
   - Synthetic UUIDs (`metadata-packagename`)
   - Dependencies stored with package names as keys

2. **General Registry (2018-2025)**
   - Modern Julia registry with proper UUIDs
   - TOML-based package metadata structure
   - Dependencies stored with UUIDs as values

### Processing Pipeline
1. **Commit Indexing**: Git commits mapped to monthly time periods
2. **Dependency Extraction**: Registry-specific dependency extraction with semantic versioning
3. **Package Index Building**: Unified indexing across both registries
4. **Matrix Generation**: Sparse adjacency matrices in SMAT format

### Key Features
- **Semantic Versioning Fix**: Proper handling of Julia version ranges (e.g., "0-2", "0.5-2")
- **Registry Transition**: Seamless handling of format changes at February 2018 transition
- **Comprehensive Coverage**: 92 dependency snapshots with corrected semantic versioning
- **Standard Library Filtering**: Julia standard library packages excluded from dependencies

## Usage Examples

### Loading in Julia
```julia
using SparseArrays, MatrixMarket

# Load a specific month's adjacency matrix
A = MatrixMarket.mmread("adj_2020-01.smat")

# Load package labels
labels = readlines("package_labels.txt")
package_names = [split(line, ",")[1] for line in labels]
```

### Loading in Python
```python
import scipy.io
import numpy as np

# Load matrix
A = scipy.io.mmread("adj_2020-01.smat")

# Load labels
with open("package_labels.txt") as f:
    labels = [line.strip().split(",") for line in f]
    package_names = [label[0] for label in labels]
    first_dates = [label[1] for label in labels]
```

## Citation

If you use this dataset in your research, please cite:

```
[Citation information to be provided]
```

## License

This dataset is released under [License to be specified].

## Technical Details

- **Matrix Properties**: Directed, unweighted, sparse
- **Sparsity**: Varies by time period (typical density < 0.1%)
- **Self-loops**: Excluded (packages don't depend on themselves)
- **Missing Data**: Handled via registry-specific extraction logic

## Quality Assurance

- Comprehensive test suite validates dependency extraction
- Manual verification against known dependency lists for major packages
- Semantic versioning logic tested and corrected
- Cross-registry consistency maintained

## Contact

For questions or issues regarding this dataset, please contact [Contact information to be provided].