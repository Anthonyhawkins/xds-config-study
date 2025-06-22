#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 TARGET

Trace a node or resource back to its source jsonnet templates and data.

This script analyzes a node file or resource directory and shows which jsonnet 
templates and source data files were used to produce the configurations.

Arguments:
    TARGET    Path to node JSON file or resource directory name

Examples:
    $0 nodes-and-resources/nodes/grpc-proxy.us-west-2.json
    $0 grpc-proxy.us-west-2.roo.service
    $0 nodes-and-resources/resources/grpc-proxy.us-west-2.roo.service/

Output shows:
    - Source jsonnet template files
    - Source data files used
    - Configuration parameters extracted from name
    - Generation commands that would recreate the files
EOF
}

log() {
    echo -e "$1" >&2
}

error() {
    log "${RED}Error: $1${NC}"
    exit 1
}

info() {
    log "${BLUE}$1${NC}"
}

success() {
    log "${GREEN}$1${NC}"
}

warning() {
    log "${YELLOW}$1${NC}"
}

parse_node_file() {
    local file_path="$1"
    local basename_file=$(basename "$file_path" .json)
    
    # Pattern: {role}.{region}.json
    if [[ "$basename_file" =~ ^([^.]+)\.([^.]+)$ ]]; then
        echo "role=${BASH_REMATCH[1]}"
        echo "region=${BASH_REMATCH[2]}"
        echo "type=node"
        return 0
    fi
    
    return 1
}

parse_resource_name() {
    local resource_name="$1"
    
    # Remove trailing slash if present
    resource_name="${resource_name%/}"
    
    # Remove path prefix if present
    resource_name=$(basename "$resource_name")
    
    # Pattern: {role}.{region}.{service}
    if [[ "$resource_name" =~ ^([^.]+)\.([^.]+)\.(.+)$ ]]; then
        echo "role=${BASH_REMATCH[1]}"
        echo "region=${BASH_REMATCH[2]}"
        echo "service=${BASH_REMATCH[3]}"
        echo "type=resource"
        return 0
    fi
    
    return 1
}

find_template_files() {
    local templates=()
    
    if [[ -f "$PROJECT_ROOT/templates/cluster.jsonnet" ]]; then
        templates+=("$PROJECT_ROOT/templates/cluster.jsonnet")
    fi
    if [[ -f "$PROJECT_ROOT/templates/loadassignment.jsonnet" ]]; then
        templates+=("$PROJECT_ROOT/templates/loadassignment.jsonnet")
    fi
    
    if [[ ${#templates[@]} -gt 0 ]]; then
        printf '%s\n' "${templates[@]}"
    fi
}

find_data_files() {
    local role="$1"
    local service="$2"
    local region="$3"
    
    local data_files=()
    
    # Check for service-specific data files
    local service_dir="$PROJECT_ROOT/roles/$role/services/$service"
    if [[ -d "$service_dir" ]]; then
        # Look for region-specific data
        if [[ -f "$service_dir/$region/profile.jsonnet" ]]; then
            data_files+=("$service_dir/$region/profile.jsonnet")
        fi
        if [[ -f "$service_dir/$region/cluster.yaml" ]]; then
            data_files+=("$service_dir/$region/cluster.yaml")
        fi
        if [[ -f "$service_dir/$region/loadassignment.yaml" ]]; then
            data_files+=("$service_dir/$region/loadassignment.yaml")
        fi
        
        # Look for service-level defaults
        if [[ -f "$service_dir/common.jsonnet" ]]; then
            data_files+=("$service_dir/common.jsonnet")
        fi
        if [[ -f "$service_dir/cluster.yaml" ]]; then
            data_files+=("$service_dir/cluster.yaml")
        fi
        if [[ -f "$service_dir/loadassignment.yaml" ]]; then
            data_files+=("$service_dir/loadassignment.yaml")
        fi
    fi
    
    # Check for role-level defaults
    local role_dir="$PROJECT_ROOT/roles/$role"
    if [[ -f "$role_dir/cluster.yaml" ]]; then
        data_files+=("$role_dir/cluster.yaml")
    fi
    if [[ -f "$role_dir/loadassignment.yaml" ]]; then
        data_files+=("$role_dir/loadassignment.yaml")
    fi
    
    if [[ ${#data_files[@]} -gt 0 ]]; then
        printf '%s\n' "${data_files[@]}"
    fi
}

show_generation_commands() {
    local role="$1"
    local service="$2"
    local region="$3"
    local type="$4"
    
    info "Generation Commands:"
    if [[ "$type" == "node" ]]; then
        echo "  # Generate all configs first, then sort by node:"
        echo "  ./scripts/generate.sh"
        echo "  ./scripts/sort.sh --build-dir build"
    else
        echo "  # Generate specific service config:"
        echo "  ./scripts/generate.sh roles/$role/services/$service/$region/"
        echo "  # or"
        echo "  ./scripts/generate-target.sh $role $service $region"
        echo ""
        echo "  # Then sort to create node structure:"
        echo "  ./scripts/sort.sh --build-dir build"
    fi
}

analyze_node_services() {
    local role="$1"
    local region="$2"
    
    info "Services in this node:"
    
    # Look for services in the role directory
    local role_dir="$PROJECT_ROOT/roles/$role/services"
    if [[ -d "$role_dir" ]]; then
        local services_found=false
        for service_dir in "$role_dir"/*; do
            if [[ -d "$service_dir" ]]; then
                local service=$(basename "$service_dir")
                # Check if this service has config for this region
                if [[ -d "$service_dir/$region" ]] || [[ -f "$service_dir/cluster.yaml" ]] || [[ -f "$service_dir/loadassignment.yaml" ]]; then
                    echo "  ✓ $service"
                    services_found=true
                fi
            fi
        done
        
        if [[ "$services_found" == false ]]; then
            echo "  No services found for $role in $region"
        fi
    else
        echo "  Role directory not found: $role_dir"
    fi
}

main() {
    if [[ $# -ne 1 ]]; then
        usage
        exit 1
    fi
    
    local target="$1"
    local parsed_info=""
    local analysis_type=""
    
    # Determine what type of target this is
    if [[ -f "$target" ]] && [[ "$target" == *.json ]]; then
        # It's a node file
        if parsed_info=$(parse_node_file "$target"); then
            analysis_type="node_file"
            success "Analyzing Node File: $(basename "$target")"
        else
            error "Unable to parse node file name pattern"
        fi
    elif [[ -d "$target" ]] || [[ "$target" =~ \. ]]; then
        # It's a resource directory or resource name
        if parsed_info=$(parse_resource_name "$target"); then
            analysis_type="resource"
            success "Analyzing Resource: $(basename "$target")"
        else
            error "Unable to parse resource name pattern"
        fi
    else
        error "Target must be a node JSON file or resource directory/name"
    fi
    
    # Extract variables
    eval "$parsed_info"
    
    echo ""
    
    # Show extracted configuration
    info "Configuration Parameters:"
    echo "  Role:    $role"
    echo "  Region:  $region"
    if [[ -n "${service:-}" ]]; then
        echo "  Service: $service"
    fi
    echo "  Type:    $type"
    echo ""
    
    # Show template files
    info "Template Files:"
    local template_files
    if template_files=$(find_template_files); then
        if [[ -z "$template_files" ]]; then
            echo "  No template files found"
        else
            while IFS= read -r template_file; do
                if [[ -f "$template_file" ]]; then
                    echo "  ✓ $template_file"
                else
                    echo "  ✗ $template_file (not found)"
                fi
            done <<< "$template_files"
        fi
    fi
    echo ""
    
    # Show data files and services
    if [[ "$type" == "resource" ]]; then
        info "Data Files:"
        local data_files
        if data_files=$(find_data_files "$role" "$service" "$region"); then
            if [[ -z "$data_files" ]]; then
                echo "  No specific data files found (using template defaults)"
            else
                while IFS= read -r data_file; do
                    if [[ -f "$data_file" ]]; then
                        echo "  ✓ $data_file"
                    else
                        echo "  ✗ $data_file (referenced but not found)"
                    fi
                done <<< "$data_files"
            fi
        fi
        echo ""
    else
        # For node files, show all services
        analyze_node_services "$role" "$region"
        echo ""
    fi
    
    # Show generation commands
    show_generation_commands "$role" "${service:-}" "$region" "$type"
    echo ""
    
    # Show target info
    info "Target Information:"
    if [[ "$analysis_type" == "node_file" ]]; then
        echo "  Node File: $target"
        if [[ -f "$target" ]]; then
            echo "  Size: $(wc -c < "$target") bytes"
            echo "  Modified: $(stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$target" 2>/dev/null || stat -c "%y" "$target" 2>/dev/null || echo "unknown")"
        fi
    else
        echo "  Resource: $target"
        local resource_path="$PROJECT_ROOT/nodes-and-resources/resources/$role.$region.$service"
        if [[ -d "$resource_path" ]]; then
            echo "  Directory: $resource_path"
            echo "  Files: $(find "$resource_path" -name "*.json" | wc -l) JSON files"
        fi
    fi
}

# Handle help
if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

main "$@"