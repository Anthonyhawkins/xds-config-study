#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

usage() {
    cat << EOF
Usage: $0 INPUT_DIR

Validate required fields and data types in profile.jsonnet files.

Checks:
    - Required fields: load_balancing_method, timeout, distribution
    - Valid timeout format (e.g., "3s", "500ms")
    - Valid load balancing methods
    - Distribution structure

Arguments:
    INPUT_DIR    Directory containing profile.jsonnet files

Examples:
    $0 roles
    $0 roles/grpc-proxy/services/foo.service
EOF
}

log_error() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    ((ERRORS++))
}

log_warning() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
    ((WARNINGS++))
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

validate_required_fields() {
    local profile_file="$1"
    local service_name="$2"
    local region="$3"
    
    local json_content
    if ! json_content=$(jsonnet "$profile_file" 2>/dev/null); then
        log_error "[$service_name/$region] Failed to parse profile.jsonnet"
        return 1
    fi
    
    local has_errors=false
    
    # Check required fields
    local required_fields=("load_balancing_method" "timeout" "distribution")
    for field in "${required_fields[@]}"; do
        if ! echo "$json_content" | jq -e ".$field" >/dev/null 2>&1; then
            log_error "[$service_name/$region] Missing required field: $field"
            has_errors=true
        fi
    done
    
    # Validate timeout format
    local timeout
    timeout=$(echo "$json_content" | jq -r '.timeout // empty')
    if [[ -n "$timeout" ]]; then
        if ! [[ "$timeout" =~ ^[0-9]+[ms|s]$ ]]; then
            log_warning "[$service_name/$region] Invalid timeout format: '$timeout' (expected: '3s' or '500ms')"
        fi
    fi
    
    # Validate load balancing method
    local lb_method
    lb_method=$(echo "$json_content" | jq -r '.load_balancing_method // empty')
    if [[ -n "$lb_method" ]]; then
        local valid_methods=("ROUND_ROBIN" "LEAST_REQUEST" "RING_HASH" "RANDOM" "MAGLEV")
        local valid=false
        for method in "${valid_methods[@]}"; do
            if [[ "$lb_method" == "$method" ]]; then
                valid=true
                break
            fi
        done
        if [[ "$valid" == "false" ]]; then
            log_warning "[$service_name/$region] Unknown load balancing method: '$lb_method'"
        fi
    fi
    
    # Validate distribution structure
    if echo "$json_content" | jq -e '.distribution' >/dev/null 2>&1; then
        # Check that each region has priority and weight
        local regions
        regions=$(echo "$json_content" | jq -r '.distribution | keys[]')
        for region_name in $regions; do
            if ! echo "$json_content" | jq -e ".distribution[\"$region_name\"].priority" >/dev/null 2>&1; then
                log_error "[$service_name/$region] Region '$region_name' missing priority field"
                has_errors=true
            fi
            if ! echo "$json_content" | jq -e ".distribution[\"$region_name\"].weight" >/dev/null 2>&1; then
                log_error "[$service_name/$region] Region '$region_name' missing weight field"
                has_errors=true
            fi
        done
        
        # Check for valid priority values (should be non-negative integers)
        echo "$json_content" | jq -r '.distribution | to_entries[] | "\(.key) \(.value.priority)"' | \
        while read -r region_name priority; do
            if ! [[ "$priority" =~ ^[0-9]+$ ]]; then
                log_error "[$service_name/$region] Region '$region_name' has invalid priority: '$priority' (should be non-negative integer)"
                has_errors=true
            fi
        done
        
        # Check for valid weight values (should be positive numbers)
        echo "$json_content" | jq -r '.distribution | to_entries[] | "\(.key) \(.value.weight)"' | \
        while read -r region_name weight; do
            if ! [[ "$weight" =~ ^[0-9]+$ ]] || [[ "$weight" -eq 0 ]]; then
                log_error "[$service_name/$region] Region '$region_name' has invalid weight: '$weight' (should be positive integer)"
                has_errors=true
            fi
        done
    fi
    
    if [[ "$has_errors" == "false" ]]; then
        log_success "[$service_name/$region] Required fields valid"
    fi
}

main() {
    if [[ $# -eq 0 ]] || [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        usage
        exit 0
    fi
    
    local input_dir="$1"
    
    if [[ ! -d "$input_dir" ]]; then
        echo "Error: Directory '$input_dir' does not exist"
        exit 1
    fi
    
    input_dir="$(cd "$input_dir" && pwd)"
    
    echo "Validating required fields in: $input_dir"
    echo ""
    
    # Find and validate all profile.jsonnet files
    while IFS= read -r -d '' profile_path; do
        local relative_path="${profile_path#$input_dir/}"
        
        local service_name region
        if [[ "$relative_path" =~ .*/services/([^/]+)/([^/]+)/profile\.jsonnet$ ]]; then
            service_name="${BASH_REMATCH[1]}"
            region="${BASH_REMATCH[2]}"
        else
            local profile_dir="$(dirname "$profile_path")"
            service_name="$(basename "$(dirname "$profile_dir")")"
            region="$(basename "$profile_dir")"
        fi
        
        validate_required_fields "$profile_path" "$service_name" "$region"
        
    done < <(find "$input_dir" -name "profile.jsonnet" -print0)
    
    echo ""
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}All required field validations passed!${NC}"
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}Found $WARNINGS warnings${NC}"
        fi
        exit 0
    else
        echo -e "${RED}Found $ERRORS field validation errors${NC}"
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}Found $WARNINGS warnings${NC}"
        fi
        exit 1
    fi
}

main "$@"