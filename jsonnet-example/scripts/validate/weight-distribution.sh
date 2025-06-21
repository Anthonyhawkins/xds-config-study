#!/bin/bash

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ERRORS=0

usage() {
    cat << EOF
Usage: $0 INPUT_DIR

Validate that weights in the same priority group sum to 100.

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

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

validate_weight_distribution() {
    local profile_file="$1"
    local service_name="$2"
    local region="$3"
    
    # Convert jsonnet to json
    local json_content
    if ! json_content=$(jsonnet "$profile_file" 2>/dev/null); then
        log_error "[$service_name/$region] Failed to parse profile.jsonnet"
        return 1
    fi
    
    # Check if distribution exists
    if ! echo "$json_content" | jq -e '.distribution' >/dev/null 2>&1; then
        log_error "[$service_name/$region] Missing 'distribution' field"
        return 1
    fi
    
    # Group regions by priority and check weight sums
    local priorities
    priorities=$(echo "$json_content" | jq -r '.distribution | to_entries[] | .value.priority' | sort -u)
    
    local all_valid=true
    for priority in $priorities; do
        local weight_sum
        weight_sum=$(echo "$json_content" | jq -r "
            .distribution | 
            to_entries[] | 
            select(.value.priority == $priority) | 
            .value.weight
        " | awk '{sum += $1} END {print sum}')
        
        if [[ "$weight_sum" != "100" ]]; then
            local regions_in_priority
            regions_in_priority=$(echo "$json_content" | jq -r "
                .distribution | 
                to_entries[] | 
                select(.value.priority == $priority) | 
                .key
            " | tr '\n' ', ' | sed 's/,$//')
            
            log_error "[$service_name/$region] Priority $priority: weight sum is $weight_sum, expected 100 (regions: $regions_in_priority)"
            all_valid=false
        fi
    done
    
    if [[ "$all_valid" == "true" ]]; then
        log_success "[$service_name/$region] Weight distribution valid"
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
    
    echo "Validating weight distribution in: $input_dir"
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
        
        validate_weight_distribution "$profile_path" "$service_name" "$region"
        
    done < <(find "$input_dir" -name "profile.jsonnet" -print0)
    
    echo ""
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}All weight distributions are valid!${NC}"
        exit 0
    else
        echo -e "${RED}Found $ERRORS weight distribution errors${NC}"
        exit 1
    fi
}

main "$@"