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
ROLE_FILTER=""
REGION_FILTER=""
PROBLEMS_ONLY=false
FORMAT="detailed"

usage() {
    cat << EOF
Usage: $0 [OPTIONS] [--build-dir DIR | --nodes-dir DIR]

Analyze weight distribution and load balancing patterns across all services.

Options:
    --build-dir DIR         Use build directory structure
    --nodes-dir DIR         Use nodes-and-resources directory structure
    --role ROLE            Filter by role
    --region REGION        Filter by region
    --problems-only        Show only services with weight issues
    --format [detailed|summary|json]  Output format (default: detailed)
    -h, --help             Show this help message

Examples:
    $0 --nodes-dir nodes-and-resources
    $0 --build-dir build --role grpc-proxy
    $0 --nodes-dir nodes-and-resources --problems-only
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
            --role)
                ROLE_FILTER="$2"
                shift 2
                ;;
            --region)
                REGION_FILTER="$2"
                shift 2
                ;;
            --problems-only)
                PROBLEMS_ONLY=true
                shift
                ;;
            --format)
                FORMAT="$2"
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
    
    # Auto-detect directory if none specified
    if [[ -z "$BUILD_DIR" && -z "$NODES_DIR" ]]; then
        if [[ -d "nodes-and-resources" ]]; then
            NODES_DIR="nodes-and-resources"
        elif [[ -d "build" ]]; then
            BUILD_DIR="build"
        else
            echo "Error: No directory specified and no default directories found"
            exit 1
        fi
    fi
    
    # Validate directories
    if [[ -n "$BUILD_DIR" && ! -d "$BUILD_DIR" ]]; then
        echo "Error: Build directory '$BUILD_DIR' does not exist"
        exit 1
    fi
    
    if [[ -n "$NODES_DIR" && ! -d "$NODES_DIR" ]]; then
        echo "Error: Nodes directory '$NODES_DIR' does not exist"
        exit 1
    fi
}

find_eds_files() {
    if [[ -n "$NODES_DIR" ]]; then
        find "$NODES_DIR/resources" -name "eds.json" 2>/dev/null
    else
        find "$BUILD_DIR" -name "eds.json" 2>/dev/null
    fi
}

extract_service_info() {
    local eds_file="$1"
    local service_name=""
    
    if [[ -n "$NODES_DIR" ]]; then
        # Extract from nodes-and-resources path: resources/role.region.service/eds.json
        service_name=$(echo "$eds_file" | sed 's|.*/resources/||; s|/eds.json||')
    else
        # Extract from build path: role/services/service/region/eds.json
        local path_parts
        path_parts=$(echo "$eds_file" | sed "s|$BUILD_DIR/||")
        if [[ "$path_parts" =~ ^([^/]+)/services/([^/]+)/([^/]+)/eds\.json$ ]]; then
            local role="${BASH_REMATCH[1]}"
            local service="${BASH_REMATCH[2]}"
            local region="${BASH_REMATCH[3]}"
            service_name="$role.$region.$service"
        fi
    fi
    
    echo "$service_name"
}

parse_service_name() {
    local service_name="$1"
    
    if [[ "$service_name" =~ ^([^.]+)\.([^.]+)\.(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}|${BASH_REMATCH[3]}"
    else
        echo "||"
    fi
}

analyze_weights() {
    local eds_file="$1"
    local service_name="$2"
    
    # Parse service name for filters
    local service_parts
    service_parts=$(parse_service_name "$service_name")
    IFS='|' read -r role region service <<< "$service_parts"
    
    # Apply filters
    if [[ -n "$ROLE_FILTER" && "$role" != "$ROLE_FILTER" ]]; then
        return
    fi
    
    if [[ -n "$REGION_FILTER" && "$region" != "$REGION_FILTER" ]]; then
        return
    fi
    
    # Extract weight information using jq
    local priority_data
    priority_data=$(jq -r '
        .resources[]?.endpoints[]? | 
        "\(.priority // 0)|\(.locality.region)|\(.load_balancing_weight // 100)"
    ' "$eds_file" 2>/dev/null)
    
    # Group by priority and calculate sums
    declare -A priority_weights
    declare -A priority_regions
    
    while IFS='|' read -r priority endpoint_region weight; do
        if [[ -n "$priority" && -n "$weight" ]]; then
            if [[ -z "${priority_weights[$priority]:-}" ]]; then
                priority_weights[$priority]=0
                priority_regions[$priority]=""
            fi
            priority_weights[$priority]=$((priority_weights[$priority] + weight))
            
            if [[ -n "${priority_regions[$priority]}" ]]; then
                priority_regions[$priority]="${priority_regions[$priority]},$endpoint_region"
            else
                priority_regions[$priority]="$endpoint_region"
            fi
        fi
    done <<< "$priority_data"
    
    # Output analysis
    local has_issues=false
    local priority_summary=""
    
    for priority in "${!priority_weights[@]}"; do
        local weight_sum=${priority_weights[$priority]}
        local regions=${priority_regions[$priority]}
        local region_count=$(echo "$regions" | tr ',' '\n' | sort -u | wc -l)
        
        if [[ $weight_sum -ne 100 ]]; then
            has_issues=true
        fi
        
        if [[ -n "$priority_summary" ]]; then
            priority_summary="$priority_summary; "
        fi
        priority_summary="$priority_summary P$priority: $weight_sum ($region_count reg)"
    done
    
    # Skip if problems-only and no issues
    if [[ "$PROBLEMS_ONLY" == "true" && "$has_issues" == "false" ]]; then
        return
    fi
    
    local issues="None"
    if [[ "$has_issues" == "true" ]]; then
        issues="Weight sum ≠ 100"
    fi
    
    echo "$service_name|$priority_summary|$issues"
}

output_detailed() {
    local temp_file=$(mktemp)
    
    echo "Weight Distribution Analysis"
    echo "==========================="
    echo ""
    
    # Collect data
    while IFS= read -r -d '' eds_file; do
        local service_name
        service_name=$(extract_service_info "$eds_file")
        if [[ -n "$service_name" ]]; then
            analyze_weights "$eds_file" "$service_name" >> "$temp_file"
        fi
    done < <(find_eds_files | sort -z)
    
    if [[ ! -s "$temp_file" ]]; then
        echo "No services found matching criteria."
        rm -f "$temp_file"
        return
    fi
    
    # Count priorities for summary
    declare -A priority_counts
    declare -A priority_totals
    
    while IFS='|' read -r service priority_info issues; do
        # Extract priority information for global summary
        if [[ "$priority_info" =~ P([0-9]+): ]]; then
            local priority="${BASH_REMATCH[1]}"
            priority_counts[$priority]=$((${priority_counts[$priority]:-0} + 1))
        fi
    done < "$temp_file"
    
    echo "Summary by Priority:"
    for priority in $(printf '%s\n' "${!priority_counts[@]}" | sort -n); do
        local count=${priority_counts[$priority]}
        echo "Priority $priority: $count services"
    done
    
    echo ""
    echo "Weight Distribution Patterns:"
    printf "┌─────────────────────────────────────┬──────────────────────┬────────────────┐\n"
    printf "│ %-35s │ %-20s │ %-14s │\n" "Service" "Priority Distribution" "Issues"
    printf "├─────────────────────────────────────┼──────────────────────┼────────────────┤\n"
    
    while IFS='|' read -r service priority_info issues; do
        # Truncate service name if too long
        local display_service="$service"
        if [[ ${#display_service} -gt 35 ]]; then
            display_service="${display_service:0:32}..."
        fi
        
        # Truncate priority info if too long
        local display_priority="$priority_info"
        if [[ ${#display_priority} -gt 20 ]]; then
            display_priority="${display_priority:0:17}..."
        fi
        
        printf "│ %-35s │ %-20s │ %-14s │\n" "$display_service" "$display_priority" "$issues"
    done < "$temp_file"
    
    printf "└─────────────────────────────────────┴──────────────────────┴────────────────┘\n"
    
    # Count issues
    local issue_count
    issue_count=$(grep -c "Weight sum" "$temp_file" || echo "0")
    
    echo ""
    echo "Issues Found: $issue_count"
    
    rm -f "$temp_file"
}

output_summary() {
    echo "Weight Distribution Summary"
    echo "=========================="
    
    local total_services=0
    local services_with_issues=0
    
    while IFS= read -r -d '' eds_file; do
        local service_name
        service_name=$(extract_service_info "$eds_file")
        if [[ -n "$service_name" ]]; then
            local analysis
            analysis=$(analyze_weights "$eds_file" "$service_name")
            if [[ -n "$analysis" ]]; then
                ((total_services++))
                if [[ "$analysis" =~ "Weight sum" ]]; then
                    ((services_with_issues++))
                fi
            fi
        fi
    done < <(find_eds_files | sort -z)
    
    echo "Total Services Analyzed: $total_services"
    echo "Services with Weight Issues: $services_with_issues"
    echo "Services with Correct Weights: $((total_services - services_with_issues))"
    
    if [[ $services_with_issues -eq 0 ]]; then
        echo -e "${GREEN}✓ All services have correct weight distributions${NC}"
    else
        echo -e "${YELLOW}⚠ $services_with_issues services have weight distribution issues${NC}"
    fi
}

output_json() {
    echo "["
    local first=true
    
    while IFS= read -r -d '' eds_file; do
        local service_name
        service_name=$(extract_service_info "$eds_file")
        if [[ -n "$service_name" ]]; then
            local analysis
            analysis=$(analyze_weights "$eds_file" "$service_name")
            if [[ -n "$analysis" ]]; then
                if [[ "$first" == "true" ]]; then
                    first=false
                else
                    echo ","
                fi
                
                IFS='|' read -r service priority_info issues <<< "$analysis"
                local has_issues="false"
                if [[ "$issues" != "None" ]]; then
                    has_issues="true"
                fi
                
                cat << EOF
  {
    "service": "$service",
    "priority_distribution": "$priority_info",
    "has_issues": $has_issues,
    "issues": "$issues"
  }
EOF
            fi
        fi
    done < <(find_eds_files | sort -z)
    
    echo ""
    echo "]"
}

main() {
    parse_args "$@"
    
    case "$FORMAT" in
        detailed)
            output_detailed
            ;;
        summary)
            output_summary
            ;;
        json)
            output_json
            ;;
        *)
            echo "Error: Invalid format option: $FORMAT" >&2
            exit 1
            ;;
    esac
}

main "$@"