#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$PROJECT_ROOT/templates"
VARS_DIR="$PROJECT_ROOT/vars"

# Default values
INPUT_DIR=""
OUTPUT_DIR=""

usage() {
    cat << EOF
Usage: $0 --in INPUT_DIR --out OUTPUT_DIR

Generate XDS configurations from jsonnet templates.

Options:
    --in INPUT_DIR      Directory containing roles with profile.jsonnet files
    --out OUTPUT_DIR    Output directory to create mirrored structure with generated configs
    -h, --help         Show this help message

Examples:
    $0 --in roles --out build
    $0 --in /path/to/roles --out /path/to/output
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --in)
                INPUT_DIR="$2"
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
    if [[ -z "$INPUT_DIR" ]]; then
        echo "Error: --in argument is required"
        usage
        exit 1
    fi
    
    if [[ -z "$OUTPUT_DIR" ]]; then
        echo "Error: --out argument is required"
        usage
        exit 1
    fi
    
    # Convert to absolute paths
    INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"
    OUTPUT_DIR="$(mkdir -p "$(dirname "$OUTPUT_DIR")" && cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
}

generate_configs() {
    local profile_path="$1"
    local profile_dir="$(dirname "$profile_path")"
    local service_name="$2"
    local output_dir="$3"
    local role_name="$4"
    local region_name="$5"
    
    echo "Generating configs for $service_name in $(basename "$profile_dir")"
    
    # Create output directory structure
    mkdir -p "$output_dir"
    
    # Change to profile directory for jsonnet execution (needed for relative imports)
    cd "$profile_dir"
    
    # Generate CDS configuration
    if [[ -f "$TEMPLATES_DIR/cluster.jsonnet" ]]; then
        jsonnet \
            --jpath "$VARS_DIR" \
            --jpath . \
            "$TEMPLATES_DIR/cluster.jsonnet" \
            --ext-str cluster_name="$service_name" \
            --ext-str role="$role_name" \
            --ext-str region="$region_name" \
            > "$output_dir/cds.json"
        echo "  Generated cds.json"
    else
        echo "  Warning: cluster.jsonnet template not found"
    fi
    
    # Generate EDS configuration
    if [[ -f "$TEMPLATES_DIR/loadassignment.jsonnet" ]]; then
        jsonnet \
            --jpath "$VARS_DIR" \
            --jpath . \
            "$TEMPLATES_DIR/loadassignment.jsonnet" \
            --ext-str cluster_name="$service_name" \
            --ext-str role="$role_name" \
            --ext-str region="$region_name" \
            > "$output_dir/eds.json"
        echo "  Generated eds.json"
    else
        echo "  Warning: loadassignment.jsonnet template not found"
    fi
}

main() {
    parse_args "$@"
    
    echo "Starting configuration generation..."
    echo "Input directory: $INPUT_DIR"
    echo "Output directory: $OUTPUT_DIR"
    echo "Templates directory: $TEMPLATES_DIR"
    echo "Variables directory: $VARS_DIR"
    echo ""
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    # Find all profile.jsonnet files and process them
    while IFS= read -r -d '' profile_path; do
        profile_dir="$(dirname "$profile_path")"
        
        # Calculate relative path from input directory
        relative_path="${profile_path#$INPUT_DIR/}"
        relative_dir="$(dirname "$relative_path")"
        
        # Create corresponding output directory
        output_dir="$OUTPUT_DIR/$relative_dir"
        
        # Extract role, service, and region from path structure
        # Look for pattern: {role}/services/{service-name}/{region}/profile.jsonnet
        if [[ "$relative_path" =~ ^([^/]+)/services/([^/]+)/([^/]+)/profile\.jsonnet$ ]]; then
            role_name="${BASH_REMATCH[1]}"
            service_name="${BASH_REMATCH[2]}"
            region_name="${BASH_REMATCH[3]}"
        else
            echo "Warning: Could not extract role/service/region from path: $profile_path"
            continue
        fi
        
        generate_configs "$profile_path" "$service_name" "$output_dir" "$role_name" "$region_name"
        
    done < <(find "$INPUT_DIR" -name "profile.jsonnet" -print0)
    
    echo ""
    echo "Configuration generation completed!"
    echo "Generated files are in: $OUTPUT_DIR"
}

# Check if required directories exist
if [[ ! -d "$TEMPLATES_DIR" ]]; then
    echo "Error: Templates directory not found at $TEMPLATES_DIR"
    exit 1
fi

if [[ ! -d "$VARS_DIR" ]]; then
    echo "Error: Variables directory not found at $VARS_DIR"
    exit 1
fi

main "$@"