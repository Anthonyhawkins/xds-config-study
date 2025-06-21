#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
BUILD_DIR="build"
NODES_DIR="nodes-and-resources"

usage() {
    cat << EOF
Usage: $0 [--build-dir DIR] [--nodes-dir DIR]

Provide a high-level overview of the entire configuration system.

Options:
    --build-dir DIR     Path to build directory (default: build)
    --nodes-dir DIR     Path to nodes-and-resources directory (default: nodes-and-resources)
    -h, --help         Show this help message

Examples:
    $0
    $0 --build-dir build --nodes-dir deployment
    $0 --nodes-dir nodes-and-resources
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --build-dir)
                BUILD_DIR="$2"
                shift 2
                ;;
            --nodes-dir)
                NODES_DIR="$2"
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
}

count_roles() {
    local dir="$1"
    local structure="$2"
    
    if [[ "$structure" == "build" ]]; then
        find "$dir" -maxdepth 1 -type d ! -path "$dir" | wc -l
    else
        find "$dir/nodes" -name "*.json" 2>/dev/null | sed 's/.*\///; s/\.json$//' | cut -d. -f1 | sort -u | wc -l
    fi
}

count_regions() {
    local dir="$1"
    local structure="$2"
    
    if [[ "$structure" == "build" ]]; then
        find "$dir" -path "*/services/*/[^/]*" -type d | sed 's/.*\///' | sort -u | wc -l
    else
        find "$dir/nodes" -name "*.json" 2>/dev/null | sed 's/.*\///; s/\.json$//' | cut -d. -f2 | sort -u | wc -l
    fi
}

count_services() {
    local dir="$1"
    local structure="$2"
    
    if [[ "$structure" == "build" ]]; then
        find "$dir" -name "cds.json" | wc -l
    else
        find "$dir/resources" -maxdepth 1 -type d ! -path "$dir/resources" 2>/dev/null | wc -l
    fi
}

count_nodes() {
    local dir="$1"
    local structure="$2"
    
    if [[ "$structure" == "build" ]]; then
        find "$dir" -path "*/services/*/[^/]*" -type d | sed 's/.*\///' | sort -u | \
        while read region; do
            find "$dir" -maxdepth 1 -type d ! -path "$dir" | sed 's/.*\///' | \
            while read role; do
                echo "$role.$region"
            done
        done | sort -u | wc -l
    else
        find "$dir/nodes" -name "*.json" 2>/dev/null | wc -l
    fi
}

analyze_service_distribution() {
    local dir="$1"
    local structure="$2"
    
    echo "Service Distribution:"
    
    if [[ "$structure" == "build" ]]; then
        # Analyze build structure
        for role_dir in "$dir"/*; do
            if [[ -d "$role_dir" ]]; then
                local role=$(basename "$role_dir")
                local service_count=$(find "$role_dir" -name "cds.json" | wc -l)
                local region_count=$(find "$role_dir" -path "*/services/*/[^/]*" -type d | sed 's/.*\///' | sort -u | wc -l)
                echo "  - $role: $service_count services across $region_count regions"
            fi
        done
    else
        # Analyze nodes structure
        for role in $(find "$dir/nodes" -name "*.json" | sed 's/.*\///; s/\.json$//' | cut -d. -f1 | sort -u); do
            local service_count=$(find "$dir/resources" -maxdepth 1 -type d -name "$role.*" | wc -l)
            local region_count=$(find "$dir/nodes" -name "$role.*.json" | wc -l)
            echo "  - $role: $service_count services across $region_count regions"
        done
    fi
}

count_files() {
    local dir="$1"
    local structure="$2"
    
    echo "File Counts:"
    
    if [[ "$structure" == "build" ]]; then
        local cds_count=$(find "$dir" -name "cds.json" | wc -l)
        local eds_count=$(find "$dir" -name "eds.json" | wc -l)
        echo "  - CDS files: $cds_count"
        echo "  - EDS files: $eds_count"
    else
        local cds_count=$(find "$dir/resources" -name "cds.json" 2>/dev/null | wc -l)
        local eds_count=$(find "$dir/resources" -name "eds.json" 2>/dev/null | wc -l)
        local node_count=$(find "$dir/nodes" -name "*.json" 2>/dev/null | wc -l)
        echo "  - CDS files: $cds_count"
        echo "  - EDS files: $eds_count"
        echo "  - Node configurations: $node_count"
    fi
}

main() {
    parse_args "$@"
    
    # Determine which structure is available
    local structure=""
    local target_dir=""
    
    if [[ -d "$NODES_DIR" ]]; then
        structure="nodes"
        target_dir="$NODES_DIR"
        echo "XDS Configuration Summary"
        echo "========================"
        echo "Nodes Directory: $(cd "$NODES_DIR" && pwd)"
    elif [[ -d "$BUILD_DIR" ]]; then
        structure="build"
        target_dir="$BUILD_DIR"
        echo "XDS Configuration Summary"
        echo "========================"
        echo "Build Directory: $(cd "$BUILD_DIR" && pwd)"
    else
        echo -e "${RED}Error: Neither $BUILD_DIR nor $NODES_DIR directory found${NC}"
        exit 1
    fi
    
    echo ""
    echo "Structure Overview:"
    
    local role_count=$(count_roles "$target_dir" "$structure")
    local region_count=$(count_regions "$target_dir" "$structure")
    local service_count=$(count_services "$target_dir" "$structure")
    local node_count=$(count_nodes "$target_dir" "$structure")
    
    echo "  - Total Roles: $role_count"
    echo "  - Total Regions: $region_count"
    echo "  - Total Services: $service_count"
    echo "  - Total Nodes: $node_count"
    
    echo ""
    analyze_service_distribution "$target_dir" "$structure"
    
    echo ""
    count_files "$target_dir" "$structure"
    
    # Basic validation
    echo ""
    echo "Status:"
    if [[ $service_count -eq 0 ]]; then
        echo -e "  ${RED}⚠ No services found${NC}"
    else
        echo -e "  ${GREEN}✓ $service_count services configured${NC}"
    fi
    
    if [[ $node_count -eq 0 ]]; then
        echo -e "  ${RED}⚠ No nodes found${NC}"
    else
        echo -e "  ${GREEN}✓ $node_count nodes available${NC}"
    fi
}

main "$@"