#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$PROJECT_ROOT/templates"
VARS_DIR="$PROJECT_ROOT/vars"

# Arguments
ROLE=""
SERVICE=""
REGION=""
OUTPUT_DIR=""

usage() {
    cat << EOF
Usage: $0 --role ROLE --service SERVICE --region REGION --out OUTPUT_DIR

Generate XDS configurations for a specific role/service/region combination.

Options:
    --role ROLE           Role name (e.g., grpc-proxy, http-proxy)
    --service SERVICE     Service name (e.g., foo.service, bar.service)
    --region REGION       Region name (e.g., us-east-1, eu-central)
    --out OUTPUT_DIR      Output directory for generated configs
    -h, --help           Show this help message

Examples:
    $0 --role grpc-proxy --service foo.service --region us-east-1 --out build
    $0 --role grpc-proxy --service bar.service --region eu-central --out /tmp/configs
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --role)
                ROLE="$2"
                shift 2
                ;;
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --region)
                REGION="$2"
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
    if [[ -z "$ROLE" ]]; then
        echo "Error: --role argument is required"
        usage
        exit 1
    fi
    
    if [[ -z "$SERVICE" ]]; then
        echo "Error: --service argument is required"
        usage
        exit 1
    fi
    
    if [[ -z "$REGION" ]]; then
        echo "Error: --region argument is required"
        usage
        exit 1
    fi
    
    if [[ -z "$OUTPUT_DIR" ]]; then
        echo "Error: --out argument is required"
        usage
        exit 1
    fi
    
    # Convert to absolute paths where needed
    OUTPUT_DIR="$(mkdir -p "$(dirname "$OUTPUT_DIR")" && cd "$(dirname "$OUTPUT_DIR")" && pwd)/$(basename "$OUTPUT_DIR")"
}

validate_inputs() {
    local roles_dir="$PROJECT_ROOT/roles"
    local profile_path="$roles_dir/$ROLE/services/$SERVICE/$REGION"
    
    # Check if role exists
    if [[ ! -d "$roles_dir/$ROLE" ]]; then
        echo "Error: Role '$ROLE' not found in $roles_dir"
        echo "Available roles:"
        ls -1 "$roles_dir" 2>/dev/null || echo "  (none)"
        exit 1
    fi
    
    # Check if service exists
    if [[ ! -d "$roles_dir/$ROLE/services/$SERVICE" ]]; then
        echo "Error: Service '$SERVICE' not found in role '$ROLE'"
        echo "Available services for $ROLE:"
        ls -1 "$roles_dir/$ROLE/services" 2>/dev/null || echo "  (none)"
        exit 1
    fi
    
    # Check if region exists
    if [[ ! -d "$profile_path" ]]; then
        echo "Error: Region '$REGION' not found for service '$SERVICE' in role '$ROLE'"
        echo "Available regions for $ROLE/$SERVICE:"
        ls -1 "$roles_dir/$ROLE/services/$SERVICE" 2>/dev/null || echo "  (none)"
        exit 1
    fi
    
    # Check if profile.jsonnet exists
    if [[ ! -f "$profile_path/profile.jsonnet" ]]; then
        echo "Error: profile.jsonnet not found at $profile_path/profile.jsonnet"
        exit 1
    fi
}

generate_configs() {
    local roles_dir="$PROJECT_ROOT/roles"
    local profile_path="$roles_dir/$ROLE/services/$SERVICE/$REGION"
    local output_path="$OUTPUT_DIR/$ROLE/services/$SERVICE/$REGION"
    
    echo "Generating configs for $ROLE/$SERVICE/$REGION"
    echo "Input: $profile_path"
    echo "Output: $output_path"
    echo ""
    
    # Create output directory
    mkdir -p "$output_path"
    
    # Change to profile directory for jsonnet execution (needed for relative imports)
    cd "$profile_path"
    
    # Generate CDS configuration
    if [[ -f "$TEMPLATES_DIR/cluster.jsonnet" ]]; then
        echo "Generating CDS configuration..."
        jsonnet \
            --jpath "$VARS_DIR" \
            --jpath . \
            "$TEMPLATES_DIR/cluster.jsonnet" \
            --ext-str cluster_name="$SERVICE" \
            > "$output_path/cds.json"
        echo "✓ Generated cds.json"
    else
        echo "Warning: cluster.jsonnet template not found at $TEMPLATES_DIR/cluster.jsonnet"
    fi
    
    # Generate EDS configuration
    if [[ -f "$TEMPLATES_DIR/loadassignment.jsonnet" ]]; then
        echo "Generating EDS configuration..."
        jsonnet \
            --jpath "$VARS_DIR" \
            --jpath . \
            "$TEMPLATES_DIR/loadassignment.jsonnet" \
            --ext-str cluster_name="$SERVICE" \
            > "$output_path/eds.json"
        echo "✓ Generated eds.json"
    else
        echo "Warning: loadassignment.jsonnet template not found at $TEMPLATES_DIR/loadassignment.jsonnet"
    fi
    
    echo ""
    echo "Configuration generation completed!"
    echo "Files generated in: $output_path"
    
    # Show generated files
    if [[ -f "$output_path/cds.json" ]] || [[ -f "$output_path/eds.json" ]]; then
        echo ""
        echo "Generated files:"
        ls -la "$output_path"/*.json 2>/dev/null || true
    fi
}

main() {
    parse_args "$@"
    
    echo "Target generation for specific role/service/region"
    echo "Role: $ROLE"
    echo "Service: $SERVICE"
    echo "Region: $REGION"
    echo "Output directory: $OUTPUT_DIR"
    echo "Templates directory: $TEMPLATES_DIR"
    echo "Variables directory: $VARS_DIR"
    echo ""
    
    validate_inputs
    generate_configs
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