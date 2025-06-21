#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
VARS_DIR="$PROJECT_ROOT/vars"

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

Validate consistency between profile distributions and endpoint definitions.

Checks:
    - All regions in distribution exist in endpoints.jsonnet
    - All endpoints have valid IP addresses and ports
    - No duplicate IP addresses across regions
    - Port consistency within regions

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

validate_ip_address() {
    local ip="$1"
    local ip_regex='^([0-9]{1,3}\.){3}[0-9]{1,3}$'
    
    if [[ ! $ip =~ $ip_regex ]]; then
        return 1
    fi
    
    # Check each octet is 0-255
    IFS='.' read -ra octets <<< "$ip"
    for octet in "${octets[@]}"; do
        if [[ $octet -gt 255 ]]; then
            return 1
        fi
    done
    
    return 0
}

validate_endpoint_consistency() {
    local profile_file="$1"
    local service_name="$2"
    local region="$3"
    
    # Check if endpoints file exists
    if [[ ! -f "$VARS_DIR/endpoints.jsonnet" ]]; then
        log_error "[$service_name/$region] endpoints.jsonnet not found at $VARS_DIR/endpoints.jsonnet"
        return 1
    fi
    
    local profile_json endpoints_json
    if ! profile_json=$(jsonnet "$profile_file" 2>/dev/null); then
        log_error "[$service_name/$region] Failed to parse profile.jsonnet"
        return 1
    fi
    
    if ! endpoints_json=$(jsonnet "$VARS_DIR/endpoints.jsonnet" 2>/dev/null); then
        log_error "[$service_name/$region] Failed to parse endpoints.jsonnet"
        return 1
    fi
    
    local has_errors=false
    
    # Check if distribution exists
    if ! echo "$profile_json" | jq -e '.distribution' >/dev/null 2>&1; then
        log_error "[$service_name/$region] Missing distribution field"
        return 1
    fi
    
    # Check if all regions in distribution exist in endpoints
    echo "$profile_json" | jq -r '.distribution | keys[]' | while read -r dist_region; do
        if ! echo "$endpoints_json" | jq -e ".gateways[\"$dist_region\"]" >/dev/null 2>&1; then
            log_error "[$service_name/$region] Region '$dist_region' in distribution not found in endpoints.jsonnet"
            has_errors=true
        else
            # Validate IP addresses for this region
            local ips
            ips=$(echo "$endpoints_json" | jq -r ".gateways[\"$dist_region\"].ips[]")
            for ip in $ips; do
                if ! validate_ip_address "$ip"; then
                    log_error "[$service_name/$region] Invalid IP address '$ip' in region '$dist_region'"
                    has_errors=true
                fi
            done
            
            # Validate port
            local port
            port=$(echo "$endpoints_json" | jq -r ".gateways[\"$dist_region\"].port")
            if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
                log_error "[$service_name/$region] Invalid port '$port' in region '$dist_region' (must be 1-65535)"
                has_errors=true
            fi
        fi
    done
    
    if [[ "$has_errors" == "false" ]]; then
        log_success "[$service_name/$region] Endpoint consistency valid"
    fi
}

check_global_consistency() {
    local endpoints_file="$VARS_DIR/endpoints.jsonnet"
    
    if [[ ! -f "$endpoints_file" ]]; then
        return 1
    fi
    
    local endpoints_json
    if ! endpoints_json=$(jsonnet "$endpoints_file" 2>/dev/null); then
        return 1
    fi
    
    echo "Checking global endpoint consistency..."
    
    # Check for duplicate IP addresses across regions
    local all_ips
    all_ips=$(echo "$endpoints_json" | jq -r '.gateways | to_entries[] | "\(.key) \(.value.ips[])"' | sort)
    
    local duplicate_ips
    duplicate_ips=$(echo "$all_ips" | awk '{print $2}' | sort | uniq -d)
    
    if [[ -n "$duplicate_ips" ]]; then
        for ip in $duplicate_ips; do
            local regions_with_ip
            regions_with_ip=$(echo "$all_ips" | grep " $ip$" | awk '{print $1}' | tr '\n' ', ' | sed 's/,$//')
            log_warning "IP address '$ip' used in multiple regions: $regions_with_ip"
        done
    fi
    
    # Check port consistency within regions (all IPs in a region should use same port)
    echo "$endpoints_json" | jq -r '.gateways | to_entries[] | "\(.key) \(.value.port)"' | \
    while read -r region port; do
        if ! [[ "$port" =~ ^[0-9]+$ ]]; then
            log_error "Region '$region' has non-numeric port: '$port'"
        fi
    done
    
    log_success "Global endpoint consistency checked"
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
    
    echo "Validating endpoint consistency in: $input_dir"
    echo "Variables directory: $VARS_DIR"
    echo ""
    
    # Global consistency check first
    check_global_consistency
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
        
        validate_endpoint_consistency "$profile_path" "$service_name" "$region"
        
    done < <(find "$input_dir" -name "profile.jsonnet" -print0)
    
    echo ""
    if [[ $ERRORS -eq 0 ]]; then
        echo -e "${GREEN}All endpoint consistency checks passed!${NC}"
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}Found $WARNINGS warnings${NC}"
        fi
        exit 0
    else
        echo -e "${RED}Found $ERRORS endpoint consistency errors${NC}"
        if [[ $WARNINGS -gt 0 ]]; then
            echo -e "${YELLOW}Found $WARNINGS warnings${NC}"
        fi
        exit 1
    fi
}

main "$@"