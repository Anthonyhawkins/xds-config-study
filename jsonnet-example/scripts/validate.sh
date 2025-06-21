#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_DIR="$SCRIPT_DIR/validate"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
Usage: $0 [OPTIONS] INPUT_DIR

Run all validation scripts on XDS configuration files.

Arguments:
    INPUT_DIR              Directory containing profile.jsonnet files

Options:
    --weight-only         Run only weight distribution validation
    --fields-only         Run only required fields validation  
    --endpoints-only      Run only endpoint consistency validation
    -h, --help           Show this help message

Available validations:
    - Weight distribution: Ensures weights per priority group sum to 100
    - Required fields: Validates required fields and data types
    - Endpoint consistency: Checks profile/endpoint consistency

Examples:
    $0 roles
    $0 --weight-only roles/grpc-proxy
    $0 --fields-only roles
EOF
}

run_validation() {
    local script="$1"
    local name="$2"
    local input_dir="$3"
    
    echo -e "\n${YELLOW}=== Running $name validation ===${NC}"
    
    if [[ -x "$script" ]]; then
        if "$script" "$input_dir"; then
            echo -e "${GREEN}✓ $name validation passed${NC}"
            return 0
        else
            echo -e "${RED}✗ $name validation failed${NC}"
            return 1
        fi
    else
        echo -e "${RED}Error: $script not found or not executable${NC}"
        return 1
    fi
}

main() {
    local input_dir=""
    local weight_only=false
    local fields_only=false
    local endpoints_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --weight-only)
                weight_only=true
                shift
                ;;
            --fields-only)
                fields_only=true
                shift
                ;;
            --endpoints-only)
                endpoints_only=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                echo "Error: Unknown option $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$input_dir" ]]; then
                    input_dir="$1"
                else
                    echo "Error: Multiple input directories specified"
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required argument
    if [[ -z "$input_dir" ]]; then
        echo "Error: INPUT_DIR is required"
        usage
        exit 1
    fi
    
    if [[ ! -d "$input_dir" ]]; then
        echo "Error: Directory '$input_dir' does not exist"
        exit 1
    fi
    
    input_dir="$(cd "$input_dir" && pwd)"
    
    echo "Running XDS configuration validation"
    echo "Input directory: $input_dir"
    echo "Validation scripts: $VALIDATE_DIR"
    
    local total_failed=0
    local total_run=0
    
    # Run specific validation if requested
    if [[ "$weight_only" == "true" ]]; then
        ((total_run++))
        if ! run_validation "$VALIDATE_DIR/weight-distribution.sh" "Weight Distribution" "$input_dir"; then
            ((total_failed++))
        fi
    elif [[ "$fields_only" == "true" ]]; then
        ((total_run++))
        if ! run_validation "$VALIDATE_DIR/required-fields.sh" "Required Fields" "$input_dir"; then
            ((total_failed++))
        fi
    elif [[ "$endpoints_only" == "true" ]]; then
        ((total_run++))
        if ! run_validation "$VALIDATE_DIR/endpoint-consistency.sh" "Endpoint Consistency" "$input_dir"; then
            ((total_failed++))
        fi
    else
        # Run all validations
        local validations=(
            "$VALIDATE_DIR/weight-distribution.sh:Weight Distribution"
            "$VALIDATE_DIR/required-fields.sh:Required Fields"
            "$VALIDATE_DIR/endpoint-consistency.sh:Endpoint Consistency"
        )
        
        for validation in "${validations[@]}"; do
            IFS=':' read -r script name <<< "$validation"
            ((total_run++))
            if ! run_validation "$script" "$name" "$input_dir"; then
                ((total_failed++))
            fi
        done
    fi
    
    # Summary
    echo ""
    echo "=== Validation Summary ==="
    echo "Total validations run: $total_run"
    echo "Passed: $((total_run - total_failed))"
    echo "Failed: $total_failed"
    
    if [[ $total_failed -eq 0 ]]; then
        echo -e "${GREEN}All validations passed! ✓${NC}"
        exit 0
    else
        echo -e "${RED}$total_failed validation(s) failed ✗${NC}"
        exit 1
    fi
}

main "$@"