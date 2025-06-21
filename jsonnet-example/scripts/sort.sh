#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Arguments
BUILD_DIR=""
OUTPUT_DIR="nodes-and-resources"

usage() {
    cat << EOF
Usage: $0 --build-dir BUILD_DIR [--out OUTPUT_DIR]

Sort generated configurations by node and create node-to-resource mappings.

This script reorganizes configurations from role/service/region structure
to a node-centric structure where nodes are identified by {role}.{region}.

Options:
    --build-dir BUILD_DIR    Directory containing generated configurations (required)
    --out OUTPUT_DIR         Output directory (default: nodes-and-resources)
    -h, --help              Show this help message

Output Structure:
    nodes-and-resources/
    ├── nodes/
    │   └── {role}.{region}.json     # Node configuration with service list
    └── resources/
        └── {role}.{region}.{service}/
            ├── cds.json             # Copied from build directory
            └── eds.json             # Copied from build directory

Examples:
    $0 --build-dir build
    $0 --build-dir build --out deployment-configs
    $0 --build-dir /path/to/generated/configs --out /path/to/sorted/configs
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-dir)
                BUILD_DIR="$2"
                shift 2
                ;;
            --out)
                OUTPUT_DIR="$2"
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
    
    # Validate required arguments
    if [[ -z "$BUILD_DIR" ]]; then
        echo "Error: --build-dir argument is required"
        usage
        exit 1
    fi
    
    if [[ ! -d "$BUILD_DIR" ]]; then
        echo "Error: Build directory '$BUILD_DIR' does not exist"
        exit 1
    fi
    
    # Convert to absolute paths
    BUILD_DIR="$(cd "$BUILD_DIR" && pwd)"
    OUTPUT_DIR="$(mkdir -p "$(dirname "$OUTPUT_DIR")" && cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
}

log_info() {
    echo -e "${GREEN}INFO: $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}"
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
}

create_output_structure() {
    local output_dir="$1"
    
    echo "Creating output directory structure..."
    mkdir -p "$output_dir/nodes"
    mkdir -p "$output_dir/resources"
    
    log_info "Created directory structure at: $output_dir"
}

process_configurations() {
    local build_dir="$1"
    local output_dir="$2"
    
    # Track nodes and their services using temporary files
    local temp_dir=$(mktemp -d)
    local total_services=0
    local total_nodes=0
    
    echo "Processing configurations from: $build_dir"
    echo ""
    
    # Find all CDS files and process them (EDS files will be in same directories)
    while IFS= read -r -d '' cds_file; do
        # Extract path components
        local relative_path="${cds_file#$build_dir/}"
        
        # Parse path: {role}/services/{service}/{region}/cds.json
        if [[ "$relative_path" =~ ^([^/]+)/services/([^/]+)/([^/]+)/cds\.json$ ]]; then
            local role="${BASH_REMATCH[1]}"
            local service="${BASH_REMATCH[2]}"
            local region="${BASH_REMATCH[3]}"
            
            # Construct service and node names
            local service_name="${role}.${region}.${service}"
            local node_name="${role}.${region}"
            
            # Directory containing the CDS/EDS files
            local source_dir="$(dirname "$cds_file")"
            local eds_file="$source_dir/eds.json"
            
            # Create resource directory
            local resource_dir="$output_dir/resources/$service_name"
            mkdir -p "$resource_dir"
            
            # Copy files to resource directory
            if [[ -f "$cds_file" ]]; then
                cp "$cds_file" "$resource_dir/cds.json"
                echo "  Copied: $relative_path → resources/$service_name/cds.json"
            else
                log_warning "CDS file not found: $cds_file"
            fi
            
            if [[ -f "$eds_file" ]]; then
                cp "$eds_file" "$resource_dir/eds.json"
                echo "  Copied: ${relative_path%cds.json}eds.json → resources/$service_name/eds.json"
            else
                log_warning "EDS file not found: $eds_file"
            fi
            
            # Track service for this node using temporary files
            local node_file="$temp_dir/${node_name}.services"
            if [[ ! -f "$node_file" ]]; then
                touch "$node_file"
                ((total_nodes++))
            fi
            echo "$service_name" >> "$node_file"
            
            ((total_services++))
        else
            log_warning "Skipping file with unexpected path pattern: $relative_path"
        fi
        
    done < <(find "$build_dir" -name "cds.json" -print0)
    
    # Generate node configuration files
    echo ""
    echo "Generating node configuration files..."
    
    for services_file in "$temp_dir"/*.services; do
        if [[ ! -f "$services_file" ]]; then
            continue
        fi
        
        local node_name=$(basename "$services_file" .services)
        local node_config_file="$output_dir/nodes/$node_name.json"
        
        # Read services from file and create JSON array
        local json_services=""
        local service_count=0
        while IFS= read -r service_name; do
            if [[ -n "$service_name" ]]; then
                if [[ -n "$json_services" ]]; then
                    json_services="$json_services, \"$service_name\""
                else
                    json_services="\"$service_name\""
                fi
                ((service_count++))
            fi
        done < "$services_file"
        
        # Create node configuration file
        cat > "$node_config_file" << EOF
{
    "services": [$json_services]
}
EOF
        
        echo "  Created: nodes/$node_name.json ($service_count services)"
    done
    
    # Clean up temporary directory
    rm -rf "$temp_dir"
    
    echo ""
    log_info "Processing completed successfully!"
    echo "Summary:"
    echo "  - Total nodes: $total_nodes"
    echo "  - Total services: $total_services"
    echo "  - Output directory: $output_dir"
}


verify_output() {
    local output_dir="$1"
    
    echo ""
    echo "Verifying output structure..."
    
    local node_count=$(find "$output_dir/nodes" -name "*.json" 2>/dev/null | wc -l)
    local resource_count=$(find "$output_dir/resources" -type d -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)
    
    echo "Verification results:"
    echo "  - Node files: $node_count"
    echo "  - Resource directories: $resource_count"
    
    if [[ $node_count -eq 0 ]]; then
        log_error "No node files were created"
        return 1
    fi
    
    if [[ $resource_count -eq 0 ]]; then
        log_error "No resource directories were created"
        return 1
    fi
    
    log_info "Output verification passed"
    return 0
}

main() {
    parse_args "$@"
    
    echo "XDS Configuration Sorting Script"
    echo "================================"
    echo "Build directory: $BUILD_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo ""
    
    # Check if output directory exists and warn user
    if [[ -d "$OUTPUT_DIR" ]]; then
        log_warning "Output directory '$OUTPUT_DIR' already exists"
        echo "Contents will be overwritten. Continue? (y/N)"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo "Operation cancelled."
            exit 0
        fi
        rm -rf "$OUTPUT_DIR"
    fi
    
    create_output_structure "$OUTPUT_DIR"
    process_configurations "$BUILD_DIR" "$OUTPUT_DIR"
    
    if verify_output "$OUTPUT_DIR"; then
        echo ""
        echo "🎉 Configuration sorting completed successfully!"
        echo ""
        echo "Next steps:"
        echo "  - Review node configurations in: $OUTPUT_DIR/nodes/"
        echo "  - Deploy resources from: $OUTPUT_DIR/resources/"
        echo "  - Original build directory preserved at: $BUILD_DIR"
    else
        log_error "Verification failed - please check the output"
        exit 1
    fi
}

main "$@"