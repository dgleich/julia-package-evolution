#!/usr/bin/env julia

"""
Full temporal graph dump script that walks through all commits and outputs
time-stamped edge edits in the format:
time i j + # added an edge at time 
time i j - # removed an edge at this time  

This script processes the entire temporal evolution of Julia package dependencies
from the earliest METADATA commit through to the latest General registry commit.
"""

include("JuliaPackageDependencies.jl")
using .JuliaPackageDependencies
using Dates
using Printf
using Graphs

const JPD = JuliaPackageDependencies

function dump_temporal_graph_edits(output_file::String = "full-temporal-graph.txt")
    println("🚀 Starting full temporal graph edge dump...")
    println("Output file: $output_file")
    println("=" ^ 60)
    
    # Open output file for writing
    open(output_file, "w") do io
        # Write header
        println(io, "# Full Temporal Julia Package Dependency Graph Edge Edits")
        println(io, "# Format: time_index package_id_i package_id_j +/-")
        println(io, "# + indicates edge added at this time")
        println(io, "# - indicates edge removed at this time")
        println(io, "# Time index starts at 1 and increments for each commit")
        println(io, "# Package IDs correspond to the combined_package_index.json")
        println(io, "#")
        
        # Initialize - start from earliest available date
        println("📅 Loading initial dependencies from earliest commit...")
        
        # Get the first available commit
        D = JPD.first_commit()
        
        println("✅ Initial load completed")
        println(@sprintf("   📊 Initial state: %d packages, %d edges", 
                length(D.packages), ne(D.g)))
        println(@sprintf("   📝 Starting from commit: %s (%s)", 
                D.c[1:7], Dates.format(D.dt, "yyyy-mm-ddTHH:MM:SS.sssZ")))
        println()
        
        # Write initial state metadata
        println(io, "# Initial commit: $(D.c)")
        println(io, "# Initial date: $(Dates.format(D.dt, "yyyy-mm-ddTHH:MM:SS.sssZ"))")
        println(io, "# Initial packages: $(length(D.packages))")
        println(io, "# Initial edges: $(ne(D.g))")
        println(io, "#")
        
        time_index = 1
        current_D = D
        commits_processed = 0
        total_edges_added = 0
        total_edges_removed = 0
        
        # Write all initial edges as + at time_index = 1
        println("📝 Writing initial edges for first commit...")
        initial_edges = 0
        for edge in edges(D.g)
            src_idx = src(edge)
            dst_idx = dst(edge)
            
            
            println(io, "$time_index $src_idx $dst_idx +")
            total_edges_added += 1
            initial_edges += 1
        end
        
        println("✅ Wrote $initial_edges initial edges for time index $time_index")
        
        # Print initial state in the progress table
        repo_str = string(D.active_repo)
        println(@sprintf("%4d | %7s | %8d | %5d | %5d | %5d | %s",
                time_index, D.c[1:7], length(D.packages), ne(D.g),
                initial_edges, 0, repo_str))
        
        # Process all commits
        println("🔄 Walking through remaining commits...")
        println("Time | Commit  | Packages | Edges | +Edge | -Edge | Active Repo")
        println("-" ^ 70)
        
        while true
            try
                new_D, delta = JPD.next_commit!(current_D)
                time_index += 1
                commits_processed += 1

                # # write edges from new_D.g
                # println("Processing commit $(new_D.c[1:7]) at time index $time_index")
                # println("   📅 Date: $(Dates.format(new_D.dt, "yyyy-mm-ddTHH:MM:SS.sssZ"))")
                # println("   📦 Packages: $(length(new_D.packages))")
                # println("   🔗 Edges: $(ne(new_D.g))")
                # println("   ➕ New edges: $(length(delta.new_edges))")
                # println("   ➖ Removed edges: $(length(delta.removed_edges))")
                # println("   🏷️ Active repo: $(delta.active_repo)")
                # # print edges for debugging
                # for edge in edges(new_D.g)
                #     src_idx = src(edge)
                #     dst_idx = dst(edge)
                #     println("   Edge: $src_idx -> $dst_idx")
                # end
                # # print edges with package names 
                # for edge in edges(new_D.g)
                #     src_idx = src(edge)
                #     dst_idx = dst(edge)
                #     src_name = JPD._get_package_name(src_idx)
                #     dst_name = JPD._get_package_name(dst_idx)
                #     println("   Edge: $src_name -> $dst_name")
                # end
                
                if length(delta.new_edges) >0  || length(delta.removed_edges) > 0
                    println(io, "# commit: $(new_D.c); date: $(Dates.format(new_D.dt, "yyyy-mm-ddTHH:MM:SS.sssZ"))")
                end
                
                # Write edge additions
                for (src_id, dst_id) in delta.new_edges
                    println(io, "$time_index $src_id $dst_id +")
                    total_edges_added += 1
                end
                
                # Write edge removals
                for (src_id, dst_id) in delta.removed_edges
                    println(io, "$time_index $src_id $dst_id -")
                    total_edges_removed += 1
                end

                # Check that the edge count matches
                @assert ne(new_D.g) == (ne(current_D.g) + length(delta.new_edges) - length(delta.removed_edges)) "Edge count mismatch after processing commit $(new_D.c)"
                
                @assert ne(new_D.g) == (total_edges_added - total_edges_removed) "Total edge count mismatch after processing commit $(new_D.c)"
                    
                # Print progress
                repo_str = string(delta.active_repo)
                println(@sprintf("%4d | %7s | %8d | %5d | %5d | %5d | %s",
                        time_index, delta.commit[1:7], length(new_D.packages), ne(new_D.g),
                        length(delta.new_edges), length(delta.removed_edges), repo_str))
                
                # Update for next iteration
                current_D = new_D
                
                # Occasional flush to ensure output is written
                if commits_processed % 100 == 0
                    flush(io)
                    println("   📝 Processed $commits_processed commits, flushed to disk")
                            # Process all commits
                    println("Time | Commit  | Packages | Edges | +Edge | -Edge | Active Repo")
                    println("-" ^ 70)
                end
                
            catch e
                if occursin("No more commits", string(e))
                    println("✅ Reached end of available commits")
                    break
                else
                    # print out error and stack trace and continue

                    println("❌ Error processing commit: $e")
                    println("🔍 Stacktrace:")
                    Base.show_backtrace(stderr, stacktrace(e))
                    break
                end
            end
        end
        
        # Write final summary to file
        println(io, "#")
        println(io, "# Final Summary:")
        println(io, "# Total commits processed: $commits_processed")
        println(io, "# Final time index: $time_index")
        println(io, "# Total edges added: $total_edges_added")
        println(io, "# Total edges removed: $total_edges_removed")
        println(io, "# Final packages: $(length(current_D.packages))")
        println(io, "# Final edges: $(ne(current_D.g))")
        println(io, "# Final commit: $(current_D.c)")
        println(io, "# Final date: $(Dates.format(current_D.dt, "yyyy-mm-ddTHH:MM:SS.sssZ"))")
        
        println("\n" * "=" ^ 60)
        println("📈 TEMPORAL GRAPH DUMP COMPLETE")
        println("=" ^ 60)
        println(@sprintf("📊 Commits processed: %d", commits_processed))
        println(@sprintf("⏰ Final time index: %d", time_index))
        println(@sprintf("➕ Total edges added: %d", total_edges_added))
        println(@sprintf("➖ Total edges removed: %d", total_edges_removed))
        println(@sprintf("📦 Final packages: %d", length(current_D.packages)))
        println(@sprintf("🔗 Final edges: %d", ne(current_D.g)))
        println(@sprintf("📝 Output written to: %s", output_file))
    end
    
    return nothing
end

function main()
    println("Julia Package Dependencies - Full Temporal Graph Edge Dump")
    println("=" ^ 60)
    println()
    
    # Check for custom output filename
    output_file = "julia-packages-temporal-graph.txt"
    if length(ARGS) > 0
        output_file = ARGS[1]
        println("🎯 Using custom output file: $output_file")
        println()
    end
    
    dump_temporal_graph_edits(output_file)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end