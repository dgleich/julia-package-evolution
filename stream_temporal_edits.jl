#!/usr/bin/env julia

"""
Stream temporal graph edits with package names instead of IDs.
Reads from temporal dump file and outputs to stdout with package names.
"""

using JSON

function stream_temporal_edits(dump_file::String = "julia-packages-temporal-graph.txt", 
                              index_file::String = "combined_package_index.json")
    
    # Load package index to convert IDs back to names
    if !isfile(index_file)
        error("Package index file not found: $index_file")
    end
    
    index_data = JSON.parsefile(index_file)
    id_to_name = Dict{Int,String}()
    
    for (name, data) in index_data["package_metadata"]
        idx = data["index"]
        id_to_name[idx] = name
    end
    
    println("# Temporal Julia Package Dependency Graph Edge Edits")
    println("# Format: time_index package_name_i package_name_j +/-")
    println("# + indicates edge added, - indicates edge removed")
    println("#")
    
    # Stream through the dump file
    open(dump_file, "r") do io
        for line in eachline(io)
            line = strip(line)
            
            # Skip comments and empty lines
            if startswith(line, "#") || isempty(line)
                continue
            end
            
            # Parse edge edit line: "time_index src_id dst_id +/-"
            parts = split(line)
            if length(parts) != 4
                continue
            end
            
            time_index = parts[1]
            src_id = parse(Int, parts[2])
            dst_id = parse(Int, parts[3])
            operation = parts[4]
            
            # Convert IDs to package names
            src_name = get(id_to_name, src_id, "UNKNOWN_$src_id")
            dst_name = get(id_to_name, dst_id, "UNKNOWN_$dst_id")
            
            # Output with package names
            println("$time_index $src_name $dst_name $operation")
        end
    end
end

function main()
    dump_file = "julia-packages-temporal-graph.txt"
    index_file = "combined_package_index.json"
    
    # Check for command line arguments
    if length(ARGS) >= 1
        dump_file = ARGS[1]
    end
    if length(ARGS) >= 2
        index_file = ARGS[2]
    end
    
    if !isfile(dump_file)
        error("Temporal dump file not found: $dump_file")
    end
    
    stream_temporal_edits(dump_file, index_file)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end