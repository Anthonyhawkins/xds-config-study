#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
NODES_DIR="nodes-and-resources"
SHOW_CONFIGS=false
FORMAT="detailed"

usage() {
    cat << EOF
Usage: $0 NODE_NAME [OPTIONS]

Show detailed information for a specific node.

Arguments:
    NODE_NAME           Full node name (e.g., grpc-proxy.us-east-1)

Options:
    --nodes-dir DIR     Path to nodes-and-resources directory (default: nodes-and-resources)
    --show-configs      Display actual configuration file content
    --format [detailed|json|simple]  Output format (default: detailed)
    -h, --help         Show this help message

Examples:
    $0 grpc-proxy.us-east-1
    $0 http-proxy.eu-central --show-configs
    $0 tcp-proxy.us-west-2 --format json
EOF
}

parse_args() {
    if [[ $# -eq 0 ]]; then
        echo "Error: NODE_NAME is required"
        usage
        exit 1
    fi
    
    NODE_NAME="$1"
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --nodes-dir)
                NODES_DIR="$2"
                shift 2
                ;;
            --show-configs)
                SHOW_CONFIGS=true
                shift
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
    
    if [[ ! -f "$NODES_DIR/nodes/$NODE_NAME.json" ]]; then
        echo "Error: Node '$NODE_NAME' not found"
        echo "Available nodes:"
        ls "$NODES_DIR/nodes"/*.json 2>/dev/null | sed 's/.*\///; s/\.json$//' | sed 's/^/  /' || echo "  (none)"
        exit 1
    fi
}

parse_node_name() {
    if [[ "$NODE_NAME" =~ ^([^.]+)\.([^.]+)$ ]]; then
        ROLE="${BASH_REMATCH[1]}"
        REGION="${BASH_REMATCH[2]}"
    else
        echo "Error: Invalid node name format: $NODE_NAME"
        echo "Expected format: role.region (e.g., grpc-proxy.us-east-1)"
        exit 1
    fi
}

get_services() {
    local node_file="$NODES_DIR/nodes/$NODE_NAME.json"
    jq -r '.services[]?' "$node_file" 2>/dev/null || echo ""
}

check_service_files() {
    local service="$1"
    local cds_status="✗ Missing"
    local eds_status="✗ Missing"
    local cds_size=""
    local eds_size=""
    
    if [[ -f "$NODES_DIR/resources/$service/cds.json" ]]; then
        cds_status="✓ Present"
        cds_size=$(stat -f%z "$NODES_DIR/resources/$service/cds.json" 2>/dev/null || stat -c%s "$NODES_DIR/resources/$service/cds.json" 2>/dev/null || echo "0")
        cds_status="✓ Present (${cds_size} bytes)"
    fi
    
    if [[ -f "$NODES_DIR/resources/$service/eds.json" ]]; then
        eds_status="✓ Present"
        eds_size=$(stat -f%z "$NODES_DIR/resources/$service/eds.json" 2>/dev/null || stat -c%s "$NODES_DIR/resources/$service/eds.json" 2>/dev/null || echo "0")
        eds_status="✓ Present (${eds_size} bytes)"
    fi
    
    echo "$service|$cds_status|$eds_status"
}

output_detailed() {
    parse_node_name
    
    echo "Node: $NODE_NAME"
    echo "========================="
    echo "Role: $ROLE"
    echo "Region: $REGION"
    
    local services
    services=$(get_services)
    local service_count=$(echo "$services" | grep -c . || echo "0")
    echo "Services: $service_count"
    
    echo ""
    echo "Service Details:"
    
    if [[ $service_count -eq 0 ]]; then
        echo "  No services configured for this node"
    else
        # Table header
        printf "┌─────────────────────────────────────┬──────────────────┬─────────────────┐\n"
        printf "│ %-35s │ %-16s │ %-15s │\n" "Service" "CDS File" "EDS File"
        printf "├─────────────────────────────────────┼──────────────────┼─────────────────┤\n"
        
        while read -r service; do
            if [[ -n "$service" ]]; then
                local service_info
                service_info=$(check_service_files "$service")
                IFS='|' read -r svc_name cds_status eds_status <<< "$service_info"
                
                # Truncate service name if too long
                local display_name="$svc_name"
                if [[ ${#display_name} -gt 35 ]]; then
                    display_name="${display_name:0:32}..."
                fi
                
                printf "│ %-35s │ %-16s │ %-15s │\n" "$display_name" "$cds_status" "$eds_status"
            fi
        done <<< "$services"
        
        printf "└─────────────────────────────────────┴──────────────────┴─────────────────┘\n"
    fi
    
    echo ""
    echo "Resource Paths:"
    echo "- Node config: $NODES_DIR/nodes/$NODE_NAME.json"
    echo "- Resources: $NODES_DIR/resources/{service}/"
    
    if [[ "$SHOW_CONFIGS" == "true" ]]; then
        echo ""
        echo "Node Configuration:"
        echo "==================="
        jq '.' "$NODES_DIR/nodes/$NODE_NAME.json"
        
        if [[ $service_count -gt 0 ]]; then
            echo ""
            echo "Service Configurations:"
            echo "======================="
            
            while read -r service; do
                if [[ -n "$service" ]]; then
                    echo ""
                    echo "Service: $service"
                    echo "---"
                    
                    if [[ -f "$NODES_DIR/resources/$service/cds.json" ]]; then
                        echo "CDS Configuration:"
                        jq '.' "$NODES_DIR/resources/$service/cds.json"
                    fi
                    
                    if [[ -f "$NODES_DIR/resources/$service/eds.json" ]]; then
                        echo ""
                        echo "EDS Configuration:"
                        jq '.' "$NODES_DIR/resources/$service/eds.json"
                    fi
                fi
            done <<< "$services"
        fi
    fi
}

output_json() {
    parse_node_name
    
    local services
    services=$(get_services)
    
    cat << EOF
{
  "node": "$NODE_NAME",
  "role": "$ROLE",
  "region": "$REGION",
  "services": [
EOF
    
    local first=true
    while read -r service; do
        if [[ -n "$service" ]]; then
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            
            local service_info
            service_info=$(check_service_files "$service")
            IFS='|' read -r svc_name cds_status eds_status <<< "$service_info"
            
            local cds_present="false"
            local eds_present="false"
            
            if [[ "$cds_status" == *"Present"* ]]; then
                cds_present="true"
            fi
            if [[ "$eds_status" == *"Present"* ]]; then
                eds_present="true"
            fi
            
            cat << EOF
    {
      "name": "$service",
      "cds_present": $cds_present,
      "eds_present": $eds_present
    }
EOF
        fi
    done <<< "$services"
    
    echo ""
    echo "  ],"
    echo "  \"node_config_path\": \"$NODES_DIR/nodes/$NODE_NAME.json\","
    echo "  \"resources_path\": \"$NODES_DIR/resources/\""
    echo "}"
}

output_simple() {
    local services
    services=$(get_services)
    
    while read -r service; do
        if [[ -n "$service" ]]; then
            echo "$service"
        fi
    done <<< "$services"
}

main() {
    parse_args "$@"
    
    case "$FORMAT" in
        detailed)
            output_detailed
            ;;
        json)
            output_json
            ;;
        simple)
            output_simple
            ;;
        *)
            echo "Error: Invalid format option: $FORMAT" >&2
            exit 1
            ;;
    esac
}

main "$@"