#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
NODES_DIR="nodes-and-resources"
ROLE_FILTER=""
REGION_FILTER=""
SORT_BY="name"
FORMAT="table"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [--nodes-dir DIR]

List all available nodes with filtering and sorting options.

Options:
    --nodes-dir DIR         Path to nodes-and-resources directory (default: nodes-and-resources)
    --role ROLE            Filter by specific role
    --region REGION        Filter by specific region
    --sort-by [name|services|role|region]  Sort output (default: name)
    --format [table|json|simple]  Output format (default: table)
    -h, --help             Show this help message

Examples:
    $0
    $0 --role grpc-proxy
    $0 --region us-east-1 --format simple
    $0 --sort-by services --format table
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --nodes-dir)
                NODES_DIR="$2"
                shift 2
                ;;
            --role)
                ROLE_FILTER="$2"
                shift 2
                ;;
            --region)
                REGION_FILTER="$2"
                shift 2
                ;;
            --sort-by)
                SORT_BY="$2"
                shift 2
                ;;
            --format)
                FORMAT="$2"
                shift 2
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Error: Unknown option $1"
                usage
                exit 1
                ;;
        esac
    done
    
    if [[ ! -d "$NODES_DIR" ]]; then
        echo "Error: Nodes directory '$NODES_DIR' does not exist"
        exit 1
    fi
    
    if [[ ! -d "$NODES_DIR/nodes" ]]; then
        echo "Error: '$NODES_DIR/nodes' directory not found"
        exit 1
    fi
}

collect_node_data() {
    local temp_file=$(mktemp)
    
    for node_file in "$NODES_DIR/nodes"/*.json; do
        if [[ ! -f "$node_file" ]]; then
            continue
        fi
        
        local node_name=$(basename "$node_file" .json)
        
        # Parse role and region from node name
        if [[ "$node_name" =~ ^([^.]+)\.([^.]+)$ ]]; then
            local role="${BASH_REMATCH[1]}"
            local region="${BASH_REMATCH[2]}"
        else
            echo "Warning: Invalid node name format: $node_name" >&2
            continue
        fi
        
        # Apply filters
        if [[ -n "$ROLE_FILTER" && "$role" != "$ROLE_FILTER" ]]; then
            continue
        fi
        
        if [[ -n "$REGION_FILTER" && "$region" != "$REGION_FILTER" ]]; then
            continue
        fi
        
        # Count services
        local service_count=0
        if [[ -f "$node_file" ]]; then
            service_count=$(jq -r '.services | length' "$node_file" 2>/dev/null || echo "0")
        fi
        
        echo "$node_name|$role|$region|$service_count" >> "$temp_file"
    done
    
    echo "$temp_file"
}

sort_data() {
    local temp_file="$1"
    
    case "$SORT_BY" in
        name)
            sort -t'|' -k1,1 "$temp_file"
            ;;
        role)
            sort -t'|' -k2,2 -k1,1 "$temp_file"
            ;;
        region)
            sort -t'|' -k3,3 -k1,1 "$temp_file"
            ;;
        services)
            sort -t'|' -k4,4nr -k1,1 "$temp_file"
            ;;
        *)
            echo "Error: Invalid sort option: $SORT_BY" >&2
            exit 1
            ;;
    esac
}

output_table() {
    local data="$1"
    
    echo "Node                      Role        Region      Services"
    echo "========================  ==========  ==========  ========"
    
    while IFS='|' read -r node_name role region service_count; do
        printf "%-24s  %-10s  %-10s  %s\n" "$node_name" "$role" "$region" "$service_count"
    done <<< "$data"
}

output_json() {
    local data="$1"
    
    echo "["
    local first=true
    while IFS='|' read -r node_name role region service_count; do
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        
        cat << EOF
  {
    "node": "$node_name",
    "role": "$role",
    "region": "$region",
    "services": $service_count
  }
EOF
    done <<< "$data"
    echo ""
    echo "]"
}

output_simple() {
    local data="$1"
    
    while IFS='|' read -r node_name role region service_count; do
        echo "$node_name"
    done <<< "$data"
}

main() {
    parse_args "$@"
    
    local temp_file=$(collect_node_data)
    
    if [[ ! -s "$temp_file" ]]; then
        echo "No nodes found matching the specified criteria."
        rm -f "$temp_file"
        exit 0
    fi
    
    local sorted_data=$(sort_data "$temp_file")
    rm -f "$temp_file"
    
    case "$FORMAT" in
        table)
            output_table "$sorted_data"
            ;;
        json)
            output_json "$sorted_data"
            ;;
        simple)
            output_simple "$sorted_data"
            ;;
        *)
            echo "Error: Invalid format option: $FORMAT" >&2
            exit 1
            ;;
    esac
}

main "$@"