#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0

usage() {
    cat << EOF
Usage: $0 BUILD_DIR

Validate unique names across generated configuration files.

Checks:
    - CDS files: 'name' field must be unique across all cds.json files
    - EDS files: 'cluster_name' field must be unique across all eds.json files

Arguments:
    BUILD_DIR    Directory containing generated configuration files

Examples:
    $0 build
    $0 /path/to/generated/configs
EOF
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    ((ERRORS++))
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

validate_unique_names() {
    local build_dir="$1"
    
    echo "Validating unique names in: $build_dir"
    echo ""
    
    # Check CDS file names for uniqueness
    echo "Checking CDS file name uniqueness..."
    local cds_names_file=$(mktemp)
    local cds_duplicates_file=$(mktemp)
    
    # Find all cds.json files and extract names
    while IFS= read -r -d '' cds_file; do
        local relative_path="${cds_file#$build_dir/}"
        local name
        if name=$(jq -r '.name // empty' "$cds_file" 2>/dev/null) && [[ -n "$name" ]]; then
            echo "$name:$relative_path" >> "$cds_names_file"
        else
            log_error "[$relative_path] Failed to extract 'name' field from CDS file"
        fi
    done < <(find "$build_dir" -name "cds.json" -print0)
    
    # Check for duplicate CDS names
    if [[ -s "$cds_names_file" ]]; then
        cut -d: -f1 "$cds_names_file" | sort | uniq -d > "$cds_duplicates_file"
        
        if [[ -s "$cds_duplicates_file" ]]; then
            while read -r duplicate_name; do
                echo -e "${RED}ERROR: Duplicate CDS name '$duplicate_name' found in files:${NC}" >&2
                ((ERRORS++))
                grep "^$duplicate_name:" "$cds_names_file" | cut -d: -f2 | sed 's/^/  - /' >&2
            done < "$cds_duplicates_file"
        else
            local cds_count=$(wc -l < "$cds_names_file")
            log_success "All $cds_count CDS names are unique"
        fi
    else
        echo "No CDS files found to validate"
    fi
    
    # Check EDS file cluster_names for uniqueness
    echo ""
    echo "Checking EDS file cluster_name uniqueness..."
    local eds_names_file=$(mktemp)
    local eds_duplicates_file=$(mktemp)
    
    # Find all eds.json files and extract cluster_names
    while IFS= read -r -d '' eds_file; do
        local relative_path="${eds_file#$build_dir/}"
        local cluster_names
        if cluster_names=$(jq -r '.resources[]?.cluster_name // empty' "$eds_file" 2>/dev/null); then
            if [[ -n "$cluster_names" ]]; then
                while read -r cluster_name; do
                    if [[ -n "$cluster_name" ]]; then
                        echo "$cluster_name:$relative_path" >> "$eds_names_file"
                    fi
                done <<< "$cluster_names"
            else
                log_error "[$relative_path] No 'cluster_name' field found in EDS resources"
            fi
        else
            log_error "[$relative_path] Failed to extract 'cluster_name' field from EDS file"
        fi
    done < <(find "$build_dir" -name "eds.json" -print0)
    
    # Check for duplicate EDS cluster_names
    if [[ -s "$eds_names_file" ]]; then
        cut -d: -f1 "$eds_names_file" | sort | uniq -d > "$eds_duplicates_file"
        
        if [[ -s "$eds_duplicates_file" ]]; then
            while read -r duplicate_name; do
                echo -e "${RED}ERROR: Duplicate EDS cluster_name '$duplicate_name' found in files:${NC}" >&2
                ((ERRORS++))
                grep "^$duplicate_name:" "$eds_names_file" | cut -d: -f2 | sed 's/^/  - /' >&2
            done < "$eds_duplicates_file"
        else
            local eds_count=$(wc -l < "$eds_names_file")
            log_success "All $eds_count EDS cluster_names are unique"
        fi
    else
        echo "No EDS files found to validate"
    fi
    
    # Clean up temp files
    rm -f "$cds_names_file" "$cds_duplicates_file" "$eds_names_file" "$eds_duplicates_file"
}

main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
        exit 0
    fi
    
    local build_dir="$1"
    
    if [[ ! -d "$build_dir" ]]; then
        echo "Error: Directory '$build_dir' does not exist"
        exit 1
    fi
    
    build_dir="$(cd "$build_dir" && pwd)"
    
    validate_unique_names "$build_dir"
    
    echo ""
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}All unique name validations passed!${NC}"
        exit 0
    else
        echo -e "${RED}Found $ERRORS unique name validation errors${NC}"
        exit 1
    fi
}

main "$@"