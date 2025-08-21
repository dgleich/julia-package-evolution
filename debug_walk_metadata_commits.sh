#!/bin/bash

# Walk through first 50 commits in METADATA.jl and show diffs
cd METADATA

echo "Walking through first 50 commits in METADATA.jl repository..."
echo "============================================================="

# Get first 50 commit hashes in chronological order
commit_hashes=($(git log --pretty=format:"%H" --reverse | head -100))

prev_commit=""
count=1

for commit in "${commit_hashes[@]}"; do
    echo ""
    echo "=========================================="
    echo "COMMIT $count/50: $commit"
    echo "=========================================="
    
    # Show commit info
    git log -1 --pretty=format:"Date: %ci%nAuthor: %an <%ae>%nMessage: %s%n" $commit
    echo ""
    
    if [ -n "$prev_commit" ]; then
        echo "FILES CHANGED:"
        git diff --name-only $prev_commit $commit
        echo ""
        echo "DIFF:"
        echo "---"
        git diff $prev_commit $commit
    else
        echo "INITIAL COMMIT - showing all files:"
        git show --name-only $commit
        echo ""
        echo "FULL INITIAL CONTENT:"
        echo "---"
        git show $commit
    fi
    
    echo ""
    echo "Press Enter to continue to next commit (or Ctrl+C to stop)..."
    read -r
    
    prev_commit=$commit
    ((count++))
done

echo "Finished walking through first 50 commits."
