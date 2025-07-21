#!/usr/bin/env python3

import json
import numpy as np
import networkx as nx
from scipy.sparse import csr_matrix
import pandas as pd
from pathlib import Path
import re
from collections import defaultdict
import plotly.graph_objects as go
import plotly.express as px
from plotly.subplots import make_subplots
import argparse

class TemporalEcosystemAnalyzer:
    """
    Python implementation of temporal ecosystem analysis for Julia packages.
    Creates interactive HTML visualizations with time slider.
    """
    
    def __init__(self, matrices_dir="matrices_fixed", package_index_file="combined_package_index.json"):
        self.matrices_dir = Path(matrices_dir)
        self.package_index_file = package_index_file
        self.package_to_index = {}
        self.index_to_package = {}
        self.load_package_index()
        
    def load_package_index(self):
        """Load package index mappings"""
        with open(self.package_index_file, 'r') as f:
            data = json.load(f)
        
        for pkg, info in data["package_metadata"].items():
            idx = info["index"] - 1  # Convert from 1-indexed to 0-indexed for Python
            self.package_to_index[pkg] = idx
            self.index_to_package[idx] = pkg
            
        print(f"Loaded {len(self.package_to_index)} package mappings")
    
    def read_smat(self, filename):
        """Read sparse matrix in SMAT format"""
        with open(filename, 'r') as f:
            # Read header
            header = f.readline().strip().split()
            m, n, nnz = int(header[0]), int(header[1]), int(header[2])
            
            # Read data
            rows, cols, values = [], [], []
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 3:
                    # SMAT is already 0-indexed, use directly
                    row = int(parts[0])
                    col = int(parts[1])
                    val = int(parts[2])
                    rows.append(row)
                    cols.append(col)
                    values.append(val)
            
            # Create sparse matrix
            return csr_matrix((values, (rows, cols)), shape=(m, n))
    
    def parse_date_from_filename(self, filename):
        """Extract date from matrix filename"""
        match = re.search(r'adj_(\d{4}-\d{2})\.smat', str(filename))
        return match.group(1) if match else None
    
    def find_package_introduction(self, package_name):
        """Find when a package was introduced"""
        with open(self.package_index_file, 'r') as f:
            data = json.load(f)
        
        if package_name in data["package_metadata"]:
            return data["package_metadata"][package_name]["first_seen"]
        else:
            raise ValueError(f"{package_name} not found in package index")
    
    def compute_recursive_dependencies(self, adj_matrix, package_idx):
        """Compute all recursive dependencies using BFS"""
        if package_idx >= adj_matrix.shape[0]:
            return set()
        
        deps = set()
        queue = []
        
        # Add direct dependencies first
        row = adj_matrix[package_idx]
        _, direct_deps = row.nonzero()
        for dep in direct_deps:
            deps.add(dep)
            queue.append(dep)
        
        print(f"  Direct dependencies: {len(direct_deps)}")
        
        # Process queue for recursive dependencies
        while queue:
            current = queue.pop(0)
            if current < adj_matrix.shape[0]:
                row = adj_matrix[current]
                _, current_deps = row.nonzero()
                for dep in current_deps:
                    if dep not in deps:
                        deps.add(dep)
                        queue.append(dep)
        
        print(f"  Total recursive dependencies: {len(deps)}")
        return deps
    
    def extract_temporal_dependency_graphs(self, package_name, start_date=None, 
                                         exclude_packages=None, include_self=True):
        """Extract dependency graphs for each time slice"""
        if exclude_packages is None:
            exclude_packages = []
        
        if package_name not in self.package_to_index:
            raise ValueError(f"{package_name} not found in package index")
        
        package_idx = self.package_to_index[package_name]
        
        if start_date is None:
            start_date = self.find_package_introduction(package_name)
        
        print(f"Analyzing {package_name} (index: {package_idx}) from {start_date}")
        
        # Get exclusion indices
        exclude_indices = set()
        for pkg in exclude_packages:
            if pkg in self.package_to_index:
                exclude_indices.add(self.package_to_index[pkg])
                print(f"Excluding: {pkg}")
        
        # Get matrix files
        matrix_files = list(self.matrices_dir.glob("adj_*.smat"))
        matrix_files = [f for f in matrix_files if self.parse_date_from_filename(f)]
        matrix_files.sort()
        
        # Filter from start date
        relevant_files = [f for f in matrix_files 
                         if self.parse_date_from_filename(f) >= start_date]
        
        print(f"Processing {len(relevant_files)} matrices from {self.parse_date_from_filename(relevant_files[0])}")
        
        temporal_graphs = {}
        temporal_deps_sets = {}
        
        for matrix_file in relevant_files:
            date_str = self.parse_date_from_filename(matrix_file)
            print(f"Processing {date_str}...")
            
            # Read matrix
            A = self.read_smat(matrix_file)
            
            # Get recursive dependencies
            deps = self.compute_recursive_dependencies(A, package_idx)
            
            # Remove excluded packages
            deps = deps - exclude_indices
            
            # Include or exclude self
            if include_self:
                deps_final = deps | {package_idx}
            else:
                deps_final = deps
            
            # Create subgraph adjacency matrix
            subgraph_A = csr_matrix((A.shape[0], A.shape[1]))
            
            # Copy edges within dependency set
            for i in deps_final:
                row = A[i]
                _, cols = row.nonzero()
                for j in cols:
                    if j in deps_final:
                        subgraph_A[i, j] = 1
            
            temporal_graphs[date_str] = subgraph_A
            temporal_deps_sets[date_str] = deps_final
            
            print(f"  Dependencies: {len(deps)}, Edges: {subgraph_A.nnz}")
        
        return temporal_graphs, temporal_deps_sets, package_idx
    
    def create_union_dependency_graph(self, temporal_graphs, temporal_deps_sets):
        """Create union graph using OR of adjacency matrices"""
        print("Creating union graph using OR of adjacency matrices...")
        
        # Find union of all dependencies
        all_deps_union = set()
        for deps in temporal_deps_sets.values():
            all_deps_union.update(deps)
        
        print(f"Total unique dependencies across all time: {len(all_deps_union)}")
        
        # Get matrix size
        first_graph = list(temporal_graphs.values())[0]
        n = first_graph.shape[0]
        
        # Create union adjacency matrix
        union_A = csr_matrix((n, n))
        
        for A_slice in temporal_graphs.values():
            union_A = union_A.maximum(A_slice)
        
        print(f"Union adjacency matrix: {n}x{n}, {union_A.nnz} edges")
        
        # Create reindexed subgraph
        deps_list = sorted(list(all_deps_union))
        
        orig_to_graph = {orig_idx: i for i, orig_idx in enumerate(deps_list)}
        graph_to_orig = {i: orig_idx for i, orig_idx in enumerate(deps_list)}
        
        # Extract subgraph
        m = len(deps_list)
        union_subgraph = csr_matrix((m, m))
        
        for i, orig_i in enumerate(deps_list):
            row = union_A[orig_i]
            _, cols = row.nonzero()
            for orig_j in cols:
                if orig_j in orig_to_graph:
                    j = orig_to_graph[orig_j]
                    union_subgraph[i, j] = 1
        
        # Create labels
        labels = [self.index_to_package.get(orig_idx, "Unknown") for orig_idx in deps_list]
        
        print(f"Union subgraph created: {m} nodes, {union_subgraph.nnz} edges")
        
        return union_subgraph, union_A, labels, orig_to_graph, graph_to_orig, deps_list, all_deps_union
    
    def cluster_by_first_appearance_in_deps(self, deps_list, temporal_deps_sets):
        """Cluster packages by first appearance in dependency list"""
        print("Clustering packages by first appearance in dependency list...")
        
        # Sort time periods to process chronologically
        time_periods = sorted(temporal_deps_sets.keys())
        
        # Track when each package first appears in the dependency list
        first_appearance = {}
        
        for period in time_periods:
            deps_in_period = temporal_deps_sets[period]
            
            for dep_idx in deps_in_period:
                # If we haven't seen this dependency before, record its first appearance
                if dep_idx not in first_appearance:
                    first_appearance[dep_idx] = period
        
        # Create clusters based on first appearance time in dependency list
        date_to_cluster = {}
        cluster_id = 0
        clusters = []
        
        for orig_idx in deps_list:
            if orig_idx in first_appearance:
                first_seen_in_deps = first_appearance[orig_idx]
                
                if first_seen_in_deps not in date_to_cluster:
                    date_to_cluster[first_seen_in_deps] = cluster_id
                    cluster_id += 1
                
                clusters.append(date_to_cluster[first_seen_in_deps])
            else:
                # Unknown package gets cluster 0 (shouldn't happen if deps_list is correct)
                clusters.append(0)
        
        print(f"Created {cluster_id} clusters based on first appearance in dependency list")
        
        # Print cluster information
        for date, cluster_id_val in sorted(date_to_cluster.items()):
            count = sum(1 for c in clusters if c == cluster_id_val)
            pkg_names = [self.index_to_package.get(deps_list[i], "Unknown") 
                        for i in range(len(clusters)) if clusters[i] == cluster_id_val]
            print(f"Cluster {cluster_id_val} ({date}): {count} packages")
            if count <= 5:  # Show package names for small clusters
                print(f"  Packages: {', '.join(pkg_names)}")
        
        return clusters, date_to_cluster
    
    def create_cluster_colors(self, clusters, min_cluster_size=5):
        """Create color map for clusters, assigning unique colors to large clusters and black to small ones"""
        print(f"Creating colors for clusters (min size: {min_cluster_size})...")
        
        # Count cluster sizes
        from collections import Counter
        cluster_counts = Counter(clusters)
        
        # Define a palette of distinct colors for large clusters
        color_palette = [
            '#1f77b4',  # blue
            '#ff7f0e',  # orange  
            '#2ca02c',  # green
            '#d62728',  # red
            '#9467bd',  # purple
            '#8c564b',  # brown
            '#e377c2',  # pink
            '#7f7f7f',  # gray
            '#bcbd22',  # olive
            '#17becf',  # cyan
            '#aec7e8',  # light blue
            '#ffbb78',  # light orange
            '#98df8a',  # light green
            '#ff9896',  # light red
            '#c5b0d5',  # light purple
            '#c49c94',  # light brown
            '#f7b6d3',  # light pink
            '#c7c7c7',  # light gray
            '#dbdb8d',  # light olive
            '#9edae5'   # light cyan
        ]
        
        # Assign colors to large clusters
        large_clusters = [cluster_id for cluster_id, count in cluster_counts.items() 
                         if count >= min_cluster_size]
        large_clusters.sort()  # Consistent ordering
        
        cluster_to_color = {}
        for i, cluster_id in enumerate(large_clusters):
            cluster_to_color[cluster_id] = color_palette[i % len(color_palette)]
        
        # Create color list for all nodes
        node_colors = []
        for cluster_id in clusters:
            if cluster_id in cluster_to_color:
                node_colors.append(cluster_to_color[cluster_id])
            else:
                node_colors.append('#000000')  # black for small clusters
        
        print(f"Assigned unique colors to {len(large_clusters)} large clusters, "
              f"black to {len(cluster_counts) - len(large_clusters)} small clusters")
        
        return node_colors, cluster_to_color
    
    def compute_layout_coordinates(self, union_subgraph, labels, layout='spring'):
        """Compute layout coordinates using NetworkX"""
        print(f"Computing {layout} layout coordinates...")
        
        # Convert to NetworkX graph
        G = nx.from_scipy_sparse_array(union_subgraph, create_using=nx.DiGraph)
        
        # Compute layout
        if layout == 'spring':
            pos = nx.spring_layout(G, iterations=1000, k=1.0)
        elif layout == 'kamada_kawai':
            pos = nx.kamada_kawai_layout(G)
        elif layout == 'circular':
            pos = nx.circular_layout(G)
        elif layout == 'random':
            pos = nx.random_layout(G)
        else:
            print(f"Unknown layout {layout}, using spring")
            pos = nx.spring_layout(G, iterations=1000, k=1.0)
        
        # Extract coordinates
        pos_x = [pos.get(i, (0, 0))[0] for i in range(len(labels))]
        pos_y = [pos.get(i, (0, 0))[1] for i in range(len(labels))]
        
        print(f"Layout computed: {len(pos_x)} node positions")
        
        return pos_x, pos_y, pos
    
    def analyze_package_ecosystem(self, package_name, start_date=None, 
                                exclude_packages=None, include_self=True, layout='spring'):
        """Main analysis function - steps 1-4"""
        print(f"=== Analyzing {package_name} Ecosystem ===")
        
        # Steps 1-2: Extract temporal dependency graphs
        temporal_graphs, temporal_deps_sets, package_idx = self.extract_temporal_dependency_graphs(
            package_name, start_date, exclude_packages, include_self)
        
        # Step 3: Create union graph
        union_subgraph, union_A, labels, orig_to_graph, graph_to_orig, deps_list, all_deps_union = self.create_union_dependency_graph(
            temporal_graphs, temporal_deps_sets)
        
        # Step 4: Compute layout coordinates
        pos_x, pos_y, positions = self.compute_layout_coordinates(union_subgraph, labels, layout)
        
        # Create clusters by first appearance in dependency list
        clusters, date_to_cluster = self.cluster_by_first_appearance_in_deps(deps_list, temporal_deps_sets)
        
        # Create colors for clusters
        node_colors, cluster_to_color = self.create_cluster_colors(clusters)
        
        return {
            'package_name': package_name,
            'package_idx': package_idx,
            'temporal_graphs': temporal_graphs,
            'temporal_deps_sets': temporal_deps_sets,
            'union_subgraph': union_subgraph,
            'union_A': union_A,
            'labels': labels,
            'orig_to_graph': orig_to_graph,
            'graph_to_orig': graph_to_orig,
            'deps_list': deps_list,
            'all_deps_union': all_deps_union,
            'clusters': clusters,
            'date_to_cluster': date_to_cluster,
            'node_colors': node_colors,
            'cluster_to_color': cluster_to_color,
            'pos_x': pos_x,
            'pos_y': pos_y,
            'positions': positions,
            'layout': layout
        }
    
    def convert_to_native_types(self, data):
        """Convert numpy types to native Python types for JSON serialization"""
        import numpy as np
        if isinstance(data, np.integer):
            return int(data)
        elif isinstance(data, np.floating):
            return float(data)
        elif isinstance(data, np.ndarray):
            return data.tolist()
        elif isinstance(data, dict):
            return {k: self.convert_to_native_types(v) for k, v in data.items()}
        elif isinstance(data, list):
            return [self.convert_to_native_types(v) for v in data]
        else:
            return data

    def create_d3_visualization(self, results, output_file="ecosystem_d3.html"):
        """Create D3.js-based temporal network visualization"""
        print(f"Creating D3.js temporal visualization...")
        
        # Prepare data structures
        temporal_graphs = results['temporal_graphs']
        temporal_deps_sets = results['temporal_deps_sets']
        time_periods = sorted(temporal_deps_sets.keys())
        
        labels = results['labels']
        pos_x = results['pos_x']
        pos_y = results['pos_y']
        clusters = results['clusters']
        orig_to_graph = results['orig_to_graph']
        union_subgraph = results['union_subgraph']
        
        # Create nodes data (fixed positions)
        nodes_data = []
        for i, label in enumerate(labels):
            nodes_data.append({
                'id': i,
                'name': label,
                'x': pos_x[i] * 300 + 400,  # Scale and center
                'y': pos_y[i] * 300 + 300,
                'cluster': clusters[i],
                'originalIndex': results['deps_list'][i]
            })
        
        # Create edges data for union graph
        edges_data = []
        rows, cols = union_subgraph.nonzero()
        for i, j in zip(rows, cols):
            edges_data.append({
                'source': int(i),
                'target': int(j)
            })
        
        # Create temporal frames data
        frames_data = []
        for period in time_periods:
            active_deps = temporal_deps_sets[period]
            temporal_matrix = temporal_graphs[period]
            
            # Get active nodes in this period
            active_nodes = []
            for orig_idx in active_deps:
                if orig_idx in orig_to_graph:
                    graph_idx = orig_to_graph[orig_idx]
                    active_nodes.append(graph_idx)
            
            # Get active edges in this period
            active_edges = []
            temp_rows, temp_cols = temporal_matrix.nonzero()
            for orig_i, orig_j in zip(temp_rows, temp_cols):
                if orig_i in orig_to_graph and orig_j in orig_to_graph:
                    graph_i = orig_to_graph[orig_i]
                    graph_j = orig_to_graph[orig_j]
                    active_edges.append({
                        'source': int(graph_i),
                        'target': int(graph_j)
                    })
            
            frames_data.append({
                'period': period,
                'nodes': active_nodes,
                'edges': active_edges,
                'nodeCount': len(active_nodes),
                'edgeCount': len(active_edges)
            })
        
        # Create color scale
        max_cluster = max(clusters)
        colors = ['#1f77b4', '#ff7f0e', '#2ca02c', '#d62728', '#9467bd', '#8c564b', '#e377c2', '#7f7f7f', '#bcbd22', '#17becf']
        while len(colors) < max_cluster + 1:
            colors.extend(colors)
        
        # Convert all data to native Python types for JSON serialization
        nodes_data = self.convert_to_native_types(nodes_data)
        edges_data = self.convert_to_native_types(edges_data)
        frames_data = self.convert_to_native_types(frames_data)
        colors = self.convert_to_native_types(colors[:max_cluster+1])
        time_periods = self.convert_to_native_types(time_periods)
        
        # Create HTML with D3.js
        html_content = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{results['package_name']} Ecosystem Evolution - D3.js</title>
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 0;
            padding: 20px;
            background-color: #f5f5f5;
        }}
        
        .container {{
            max-width: 1400px;
            margin: 0 auto;
            background-color: white;
            padding: 20px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        
        h1 {{
            text-align: center;
            color: #333;
            margin-bottom: 30px;
        }}
        
        .controls {{
            text-align: center;
            margin-bottom: 20px;
            padding: 15px;
            background-color: #f8f9fa;
            border-radius: 5px;
        }}
        
        .controls button {{
            margin: 0 5px;
            padding: 8px 16px;
            background-color: #007bff;
            color: white;
            border: none;
            border-radius: 4px;
            cursor: pointer;
        }}
        
        .controls button:hover {{
            background-color: #0056b3;
        }}
        
        .controls button:disabled {{
            background-color: #6c757d;
            cursor: not-allowed;
        }}
        
        .time-slider {{
            width: 80%;
            margin: 10px 0;
        }}
        
        .info-panel {{
            display: flex;
            justify-content: space-between;
            margin-bottom: 20px;
            padding: 10px;
            background-color: #e9ecef;
            border-radius: 5px;
        }}
        
        .info-item {{
            text-align: center;
        }}
        
        .info-value {{
            font-size: 24px;
            font-weight: bold;
            color: #007bff;
        }}
        
        .info-label {{
            font-size: 14px;
            color: #666;
        }}
        
        #visualization {{
            width: 100%;
            height: 700px;
            border: 1px solid #ddd;
            border-radius: 5px;
            background-color: #fafafa;
        }}
        
        .node {{
            stroke: #fff;
            stroke-width: 2px;
            cursor: pointer;
        }}
        
        .link {{
            stroke: #999;
            stroke-opacity: 0.6;
            stroke-width: 2px;
        }}
        
        .node-label {{
            font-size: 10px;
            fill: #333;
            text-anchor: middle;
            pointer-events: none;
        }}
        
        .tooltip {{
            position: absolute;
            background-color: rgba(0, 0, 0, 0.8);
            color: white;
            padding: 8px;
            border-radius: 4px;
            font-size: 12px;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.2s;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>{results['package_name']} Ecosystem Evolution ({time_periods[0]} - {time_periods[-1]})</h1>
        
        <div class="info-panel">
            <div class="info-item">
                <div class="info-value" id="current-period">{time_periods[0]}</div>
                <div class="info-label">Current Period</div>
            </div>
            <div class="info-item">
                <div class="info-value" id="current-nodes">{frames_data[0]['nodeCount']}</div>
                <div class="info-label">Active Dependencies</div>
            </div>
            <div class="info-item">
                <div class="info-value" id="current-edges">{frames_data[0]['edgeCount']}</div>
                <div class="info-label">Active Edges</div>
            </div>
            <div class="info-item">
                <div class="info-value" id="total-dependencies">{len(results['all_deps_union'])}</div>
                <div class="info-label">Total Dependencies Ever</div>
            </div>
        </div>
        
        <div class="controls">
            <button id="play-btn">Play</button>
            <button id="pause-btn">Pause</button>
            <button id="reset-btn">Reset</button>
            <label for="speed-slider">Speed: </label>
            <input type="range" id="speed-slider" min="100" max="2000" value="800" step="100">
            <span id="speed-value">800ms</span>
        </div>
        
        <div class="controls">
            <input type="range" id="time-slider" class="time-slider" min="0" max="{len(time_periods)-1}" value="0">
            <div id="time-label">{time_periods[0]}</div>
        </div>
        
        <div id="visualization"></div>
    </div>
    
    <div class="tooltip" id="tooltip"></div>
    
    <script>
        // Data
        const nodes = {json.dumps(nodes_data)};
        const edges = {json.dumps(edges_data)};
        const frames = {json.dumps(frames_data)};
        const colors = {json.dumps(colors[:max_cluster+1])};
        const timePeriods = {json.dumps(time_periods)};
        
        // Visualization setup
        const width = 1360;
        const height = 700;
        let currentFrame = 0;
        let isPlaying = false;
        let playInterval;
        
        const svg = d3.select("#visualization")
            .append("svg")
            .attr("width", width)
            .attr("height", height);
        
        const g = svg.append("g");
        
        // Add zoom behavior
        const zoom = d3.zoom()
            .scaleExtent([0.1, 4])
            .on("zoom", function(event) {{
                g.attr("transform", event.transform);
            }});
        
        svg.call(zoom);
        
        // Tooltip
        const tooltip = d3.select("#tooltip");
        
        // Create links and nodes groups
        const linksGroup = g.append("g").attr("class", "links");
        const nodesGroup = g.append("g").attr("class", "nodes");
        const labelsGroup = g.append("g").attr("class", "labels");
        
        function updateVisualization() {{
            const frame = frames[currentFrame];
            const activeNodeIds = new Set(frame.nodes);
            
            // Update info panel
            document.getElementById('current-period').textContent = frame.period;
            document.getElementById('current-nodes').textContent = frame.nodeCount;
            document.getElementById('current-edges').textContent = frame.edgeCount;
            
            // Filter data for current frame
            const activeNodes = nodes.filter(n => activeNodeIds.has(n.id));
            const activeEdges = frame.edges;
            
            // Update links
            const links = linksGroup.selectAll(".link")
                .data(activeEdges, d => d.source + "-" + d.target);
            
            links.exit()
                .transition()
                .duration(300)
                .style("opacity", 0)
                .remove();
            
            links.enter()
                .append("line")
                .attr("class", "link")
                .style("opacity", 0)
                .transition()
                .duration(300)
                .style("opacity", 0.6)
                .attr("x1", d => nodes[d.source].x)
                .attr("y1", d => nodes[d.source].y)
                .attr("x2", d => nodes[d.target].x)
                .attr("y2", d => nodes[d.target].y);
            
            links.transition()
                .duration(300)
                .attr("x1", d => nodes[d.source].x)
                .attr("y1", d => nodes[d.source].y)
                .attr("x2", d => nodes[d.target].x)
                .attr("y2", d => nodes[d.target].y);
            
            // Update nodes
            const nodeElements = nodesGroup.selectAll(".node")
                .data(activeNodes, d => d.id);
            
            nodeElements.exit()
                .transition()
                .duration(300)
                .attr("r", 0)
                .style("opacity", 0)
                .remove();
            
            const nodeEnter = nodeElements.enter()
                .append("circle")
                .attr("class", "node")
                .attr("r", 0)
                .style("opacity", 0)
                .attr("cx", d => d.x)
                .attr("cy", d => d.y)
                .attr("fill", d => colors[d.cluster])
                .on("mouseover", function(event, d) {{
                    tooltip.style("opacity", 1)
                        .html(`<strong>${{d.name}}</strong><br/>Cluster: ${{d.cluster}}`)
                        .style("left", (event.pageX + 10) + "px")
                        .style("top", (event.pageY - 10) + "px");
                }})
                .on("mouseout", function() {{
                    tooltip.style("opacity", 0);
                }});
            
            nodeEnter.transition()
                .duration(300)
                .attr("r", 6)
                .style("opacity", 1);
            
            nodeElements.transition()
                .duration(300)
                .attr("cx", d => d.x)
                .attr("cy", d => d.y);
            
            // Update labels (show subset for readability)
            const importantNodes = activeNodes.filter(d => Math.random() < 0.2 || d.name === "{results['package_name']}");
            
            const labels = labelsGroup.selectAll(".node-label")
                .data(importantNodes, d => d.id);
            
            labels.exit()
                .transition()
                .duration(300)
                .style("opacity", 0)
                .remove();
            
            labels.enter()
                .append("text")
                .attr("class", "node-label")
                .text(d => d.name)
                .attr("x", d => d.x)
                .attr("y", d => d.y + 15)
                .style("opacity", 0)
                .transition()
                .duration(300)
                .style("opacity", 1);
            
            labels.transition()
                .duration(300)
                .attr("x", d => d.x)
                .attr("y", d => d.y + 15);
        }}
        
        function play() {{
            if (isPlaying) return;
            isPlaying = true;
            
            const speed = parseInt(document.getElementById('speed-slider').value);
            playInterval = setInterval(() => {{
                currentFrame++;
                if (currentFrame >= frames.length) {{
                    currentFrame = 0;
                }}
                
                updateVisualization();
                document.getElementById('time-slider').value = currentFrame;
                document.getElementById('time-label').textContent = frames[currentFrame].period;
            }}, speed);
            
            document.getElementById('play-btn').disabled = true;
            document.getElementById('pause-btn').disabled = false;
        }}
        
        function pause() {{
            isPlaying = false;
            clearInterval(playInterval);
            document.getElementById('play-btn').disabled = false;
            document.getElementById('pause-btn').disabled = true;
        }}
        
        function reset() {{
            pause();
            currentFrame = 0;
            updateVisualization();
            document.getElementById('time-slider').value = 0;
            document.getElementById('time-label').textContent = frames[0].period;
        }}
        
        // Event listeners
        document.getElementById('play-btn').addEventListener('click', play);
        document.getElementById('pause-btn').addEventListener('click', pause);
        document.getElementById('reset-btn').addEventListener('click', reset);
        
        document.getElementById('time-slider').addEventListener('input', function() {{
            currentFrame = parseInt(this.value);
            updateVisualization();
            document.getElementById('time-label').textContent = frames[currentFrame].period;
        }});
        
        document.getElementById('speed-slider').addEventListener('input', function() {{
            document.getElementById('speed-value').textContent = this.value + 'ms';
            if (isPlaying) {{
                pause();
                play();
            }}
        }});
        
        // Initialize
        updateVisualization();
    </script>
</body>
</html>'''
        
        with open(output_file, 'w') as f:
            f.write(html_content)
        
        print(f"D3.js visualization saved to {output_file}")
        
    def create_interactive_visualization(self, results, output_file="ecosystem_visualization.html"):
        """Create interactive HTML visualization with time slider"""
        print(f"Creating interactive visualization...")
        
        # Prepare data for all time periods
        temporal_deps_sets = results['temporal_deps_sets']
        time_periods = sorted(temporal_deps_sets.keys())
        
        labels = results['labels']
        pos_x = results['pos_x']
        pos_y = results['pos_y']
        clusters = results['clusters']
        orig_to_graph = results['orig_to_graph']
        
        # Create color map for clusters
        unique_clusters = list(set(clusters))
        colors = px.colors.qualitative.Set3[:len(unique_clusters)]
        cluster_colors = {cluster: colors[i % len(colors)] for i, cluster in enumerate(unique_clusters)}
        
        # Prepare frames for animation
        frames = []
        
        for period in time_periods:
            active_deps = temporal_deps_sets[period]
            active_deps_list = list(active_deps)  # Convert set to list
            
            # Filter to active nodes
            active_indices = []
            frame_x, frame_y, frame_labels, frame_colors = [], [], [], []
            
            for orig_idx in active_deps:
                if orig_idx in orig_to_graph:
                    graph_idx = orig_to_graph[orig_idx]
                    active_indices.append(graph_idx)
                    frame_x.append(pos_x[graph_idx])
                    frame_y.append(pos_y[graph_idx])
                    frame_labels.append(labels[graph_idx])
                    frame_colors.append(cluster_colors[clusters[graph_idx]])
            
            # Create frame
            frame = go.Frame(
                data=[
                    go.Scatter(
                        x=frame_x,
                        y=frame_y,
                        mode='markers+text',
                        text=frame_labels,
                        textposition='top center',
                        marker=dict(
                            size=8,
                            color=frame_colors,
                            line=dict(width=1, color='white')
                        ),
                        hoverinfo='text',
                        hovertext=[f"{label}<br>Cluster: {clusters[active_indices[i]]}" 
                                  for i, label in enumerate(frame_labels)],
                        name=f"Dependencies {period}"
                    )
                ],
                name=period
            )
            frames.append(frame)
        
        # Create initial plot (first time period)
        first_period = time_periods[0]
        active_deps = temporal_deps_sets[first_period]
        
        initial_x, initial_y, initial_labels, initial_colors = [], [], [], []
        for orig_idx in active_deps:
            if orig_idx in orig_to_graph:
                graph_idx = orig_to_graph[orig_idx]
                initial_x.append(pos_x[graph_idx])
                initial_y.append(pos_y[graph_idx])
                initial_labels.append(labels[graph_idx])
                initial_colors.append(cluster_colors[clusters[graph_idx]])
        
        # Create figure
        fig = go.Figure(
            data=[
                go.Scatter(
                    x=initial_x,
                    y=initial_y,
                    mode='markers+text',
                    text=initial_labels,
                    textposition='top center',
                    marker=dict(
                        size=8,
                        color=initial_colors,
                        line=dict(width=1, color='white')
                    ),
                    hoverinfo='text',
                    hovertext=[f"{label}<br>Cluster: {clusters[orig_to_graph[orig_idx]]}" 
                              for i, (label, orig_idx) in enumerate(zip(initial_labels, list(active_deps)))],
                    name=f"Dependencies {first_period}"
                )
            ],
            frames=frames
        )
        
        # Add animation controls
        fig.update_layout(
            title=f"{results['package_name']} Ecosystem Evolution",
            xaxis=dict(title="X Position", showgrid=False),
            yaxis=dict(title="Y Position", showgrid=False),
            showlegend=False,
            updatemenus=[
                dict(
                    type="buttons",
                    direction="left",
                    buttons=list([
                        dict(
                            args=[{"frame": {"duration": 500, "redraw": True},
                                  "transition": {"duration": 300}}],
                            label="Play",
                            method="animate"
                        ),
                        dict(
                            args=[{"frame": {"duration": 0, "redraw": True},
                                  "mode": "immediate",
                                  "transition": {"duration": 0}}],
                            label="Pause",
                            method="animate"
                        )
                    ]),
                    pad={"r": 10, "t": 87},
                    showactive=False,
                    x=0.011,
                    xanchor="right",
                    y=0,
                    yanchor="top"
                ),
            ],
            sliders=[
                dict(
                    active=0,
                    yanchor="top",
                    xanchor="left",
                    currentvalue={
                        "font": {"size": 20},
                        "prefix": "Period:",
                        "visible": True,
                        "xanchor": "right"
                    },
                    transition={"duration": 300, "easing": "cubic-in-out"},
                    pad={"b": 10, "t": 50},
                    len=0.9,
                    x=0.1,
                    y=0,
                    steps=[
                        dict(
                            args=[
                                [period],
                                {"frame": {"duration": 300, "redraw": True},
                                 "mode": "immediate",
                                 "transition": {"duration": 300}}
                            ],
                            label=period,
                            method="animate"
                        )
                        for period in time_periods
                    ]
                )
            ]
        )
        
        # Save to HTML
        fig.write_html(output_file)
        print(f"Interactive visualization saved to {output_file}")
        
        return fig


def main():
    parser = argparse.ArgumentParser(description='Temporal Ecosystem Visualization')
    parser.add_argument('package', help='Package name to analyze')
    parser.add_argument('--start-date', help='Start date (YYYY-MM)')
    parser.add_argument('--exclude', nargs='*', default=[], help='Packages to exclude')
    parser.add_argument('--include-self', action='store_true', default=True, help='Include target package')
    parser.add_argument('--exclude-self', action='store_true', help='Exclude target package')
    parser.add_argument('--layout', choices=['spring', 'kamada_kawai', 'circular', 'random'], 
                       default='spring', help='Layout algorithm')
    parser.add_argument('--output', default='ecosystem_visualization.html', help='Output HTML file')
    
    args = parser.parse_args()
    
    # Handle include_self logic
    include_self = args.include_self and not args.exclude_self
    
    # Create analyzer
    analyzer = TemporalEcosystemAnalyzer()
    
    # Run analysis
    results = analyzer.analyze_package_ecosystem(
        args.package, 
        args.start_date, 
        args.exclude, 
        include_self, 
        args.layout
    )
    
    # Create D3.js visualization
    analyzer.create_d3_visualization(results, args.output)
    
    print(f"Analysis complete! Open {args.output} in your browser.")


if __name__ == "__main__":
    main()