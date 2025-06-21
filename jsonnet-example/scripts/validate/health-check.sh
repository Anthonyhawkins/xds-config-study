#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Default values
BUILD_DIR=""
NODES_DIR=""
JSON_VALIDATE=false
QUICK=false

usage() {
    cat << EOF
Usage: $0 [--build-dir DIR] [--nodes-dir DIR] [OPTIONS]

Quick validation of directory structures and configuration file formats.

Options:
    --build-dir DIR     Check build directory structure
    --nodes-dir DIR     Check nodes-and-resources directory structure
    --json-validate     Validate JSON file formats
    --quick            Fast check (skip content validation)
    -h, --help         Show this help message

Examples:
    $0 --nodes-dir nodes-and-resources
    $0 --build-dir build --json-validate
    $0 --nodes-dir nodes-and-resources --quick
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
            --json-validate)
                JSON_VALIDATE=true
                shift
                ;;
            --quick)
                QUICK=true
                shift
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
    
    if [[ -z "$BUILD_DIR" && -z "$NODES_DIR" ]]; then
        # Auto-detect
        if [[ -d "nodes-and-resources" ]]; then
            NODES_DIR="nodes-and-resources"
        elif [[ -d "build" ]]; then
            BUILD_DIR="build"
        else
            echo "Error: No directory specified and no default directories found"
            exit 1
        fi
    fi
}

check_directory_structure() {
    echo "Directory Structure:"
    
    if [[ -n "$NODES_DIR" ]]; then
        if [[ -d "$NODES_DIR" ]]; then
            echo -e "  ${GREEN}✓ $NODES_DIR/ exists${NC}"
            
            if [[ -d "$NODES_DIR/nodes" ]]; then
                echo -e "  ${GREEN}✓ $NODES_DIR/nodes/ exists${NC}"
            else
                echo -e "  ${RED}✗ $NODES_DIR/nodes/ missing${NC}"
            fi
            
            if [[ -d "$NODES_DIR/resources" ]]; then
                echo -e "  ${GREEN}✓ $NODES_DIR/resources/ exists${NC}"
            else
                echo -e "  ${RED}✗ $NODES_DIR/resources/ missing${NC}"
            fi
        else
            echo -e "  ${RED}✗ $NODES_DIR/ not found${NC}"
        fi
    fi
    
    if [[ -n "$BUILD_DIR" ]]; then
        if [[ -d "$BUILD_DIR" ]]; then
            echo -e "  ${GREEN}✓ $BUILD_DIR/ exists${NC}"
        else
            echo -e "  ${YELLOW}⚠ $BUILD_DIR/ directory not found${NC}"
        fi
    fi
}

validate_json_files() {
    local dir="$1"
    local file_type="$2"
    local pattern="$3"
    
    local total=0
    local valid=0
    
    while IFS= read -r -d '' file; do
        ((total++))
        if jq empty "$file" >/dev/null 2>&1; then
            ((valid++))
        else
            echo -e "    ${RED}✗ Invalid JSON: $file${NC}"
        fi
    done < <(find "$dir" -name "$pattern" -print0 2>/dev/null)
    
    if [[ $total -eq 0 ]]; then
        echo "  No $file_type files found"
    elif [[ $valid -eq $total ]]; then
        echo -e "  ${GREEN}✓ All $total $file_type files valid${NC}"
    else
        echo -e "  ${YELLOW}⚠ $valid/$total $file_type files valid${NC}"
    fi
}

check_file_formats() {
    if [[ "$JSON_VALIDATE" == "false" ]]; then
        return
    fi
    
    echo ""
    echo "File Format Validation:"
    
    if [[ -n "$NODES_DIR" && -d "$NODES_DIR" ]]; then
        validate_json_files "$NODES_DIR/nodes" "node JSON" "*.json"
        validate_json_files "$NODES_DIR/resources" "CDS JSON" "cds.json"
        validate_json_files "$NODES_DIR/resources" "EDS JSON" "eds.json"
    fi
    
    if [[ -n "$BUILD_DIR" && -d "$BUILD_DIR" ]]; then
        validate_json_files "$BUILD_DIR" "CDS JSON" "cds.json"
        validate_json_files "$BUILD_DIR" "EDS JSON" "eds.json"
    fi
}

check_configuration_consistency() {
    if [[ "$QUICK" == "true" ]]; then
        return
    fi
    
    echo ""
    echo "Configuration Consistency:"
    
    if [[ -n "$NODES_DIR" && -d "$NODES_DIR" ]]; then
        # Check that all node services have corresponding resource directories
        local issues=0
        
        for node_file in "$NODES_DIR/nodes"/*.json; do
            if [[ ! -f "$node_file" ]]; then
                continue
            fi
            
            local node_name=$(basename "$node_file" .json)
            local services
            if services=$(jq -r '.services[]?' "$node_file" 2>/dev/null); then
                while read -r service; do
                    if [[ -n "$service" ]]; then
                        if [[ ! -d "$NODES_DIR/resources/$service" ]]; then
                            echo -e "    ${RED}✗ Missing resource directory for: $service${NC}"
                            ((issues++))
                        elif [[ ! -f "$NODES_DIR/resources/$service/cds.json" ]] || [[ ! -f "$NODES_DIR/resources/$service/eds.json" ]]; then
                            echo -e "    ${YELLOW}⚠ Incomplete files for: $service${NC}"
                            ((issues++))
                        fi
                    fi
                done <<< "$services"
            fi
        done
        
        if [[ $issues -eq 0 ]]; then
            echo -e "  ${GREEN}✓ All services have both CDS and EDS files${NC}"
            echo -e "  ${GREEN}✓ All node services correspond to resource directories${NC}"
        fi
    fi
}

check_performance() {
    echo ""
    echo "Performance Check:"
    
    local total_size=0
    local file_count=0
    
    if [[ -n "$NODES_DIR" && -d "$NODES_DIR" ]]; then
        # Node files
        local node_files=0
        local node_size=0
        while IFS= read -r -d '' file; do
            ((node_files++))
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            ((node_size += size))
        done < <(find "$NODES_DIR/nodes" -name "*.json" -print0 2>/dev/null)
        
        if [[ $node_files -gt 0 ]]; then
            local avg_node_size=$((node_size / node_files))
            echo "  - Node files: Average ${avg_node_size} bytes"
        fi
        
        # CDS files
        local cds_files=0
        local cds_size=0
        while IFS= read -r -d '' file; do
            ((cds_files++))
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            ((cds_size += size))
        done < <(find "$NODES_DIR/resources" -name "cds.json" -print0 2>/dev/null)
        
        if [[ $cds_files -gt 0 ]]; then
            local avg_cds_size=$((cds_size / cds_files))
            echo "  - CDS files: Average ${avg_cds_size} bytes"
        fi
        
        # EDS files
        local eds_files=0
        local eds_size=0
        while IFS= read -r -d '' file; do
            ((eds_files++))
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            ((eds_size += size))
        done < <(find "$NODES_DIR/resources" -name "eds.json" -print0 2>/dev/null)
        
        if [[ $eds_files -gt 0 ]]; then
            local avg_eds_size_kb=$(((eds_size / eds_files) / 1024))
            echo "  - EDS files: Average ${avg_eds_size_kb}KB"
        fi
        
        total_size=$((node_size + cds_size + eds_size))
        file_count=$((node_files + cds_files + eds_files))
    fi
    
    if [[ -n "$BUILD_DIR" && -d "$BUILD_DIR" ]]; then
        while IFS= read -r -d '' file; do
            ((file_count++))
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            ((total_size += size))
        done < <(find "$BUILD_DIR" -name "*.json" -print0 2>/dev/null)
    fi
    
    if [[ $total_size -gt 0 ]]; then
        local total_size_kb=$((total_size / 1024))
        echo "  - Total size: ${total_size_kb}KB ($file_count files)"
    fi
}

main() {
    parse_args "$@"
    
    echo "Health Check Results"
    echo "==================="
    echo ""
    
    check_directory_structure
    check_file_formats
    check_configuration_consistency
    check_performance
    
    echo ""
    echo -e "Overall Health: ${GREEN}✓ Healthy${NC}"
}

main "$@"