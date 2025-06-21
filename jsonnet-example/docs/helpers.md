# Show Scripts Helper Documentation

This document provides comprehensive documentation for the show scripts - a suite of tools for exploring, analyzing, and reasoning about XDS configurations.

## Overview

The show scripts are located in `scripts/show/` and provide visibility into the XDS configuration system. They help users:
- Discover and explore configuration structures
- Analyze service distribution and patterns
- Validate and compare different organizational approaches
- Search and filter configurations efficiently

## Quick Reference

| Script | Purpose | Primary Directory |
|--------|---------|-------------------|
| `summary.sh` | High-level system overview | Both build/ and nodes-and-resources/ |
| `list-nodes.sh` | List and filter nodes | nodes-and-resources/ |
| `inspect-node.sh` | Detailed node information | nodes-and-resources/ |
| `health-check.sh` | System health validation | Both (in validate/) |

## Script Details

### `scripts/show/summary.sh`

**Purpose**: Provides a high-level overview of the entire XDS configuration system.

**Usage**:
```bash
./scripts/show/summary.sh [--build-dir DIR] [--nodes-dir DIR]
```

**Key Features**:
- Auto-detects available directory structure (build/ or nodes-and-resources/)
- Counts roles, regions, services, and nodes
- Analyzes service distribution across roles
- Provides basic health status

**Example Output**:
```
XDS Configuration Summary
========================
Nodes Directory: /path/to/nodes-and-resources

Structure Overview:
  - Total Roles: 3
  - Total Regions: 3
  - Total Services: 20
  - Total Nodes: 9

Service Distribution:
  - grpc-proxy: 13 services across 3 regions
  - http-proxy: 4 services across 3 regions
  - tcp-proxy: 3 services across 3 regions

File Counts:
  - CDS files: 20
  - EDS files: 20
  - Node configurations: 9
```

**When to Use**:
- Getting started with understanding the system
- Quick health check after configuration changes
- Determining what structure is available (build vs nodes)

---

### `scripts/show/list-nodes.sh`

**Purpose**: Lists all available nodes with filtering and sorting capabilities.

**Usage**:
```bash
./scripts/show/list-nodes.sh [OPTIONS] [--nodes-dir DIR]
```

**Key Features**:
- Filter by role or region
- Sort by name, services count, role, or region
- Multiple output formats (table, JSON, simple)
- Service count per node

**Example Output**:
```
Node                      Role        Region      Services
========================  ==========  ==========  ========
grpc-proxy.eu-central     grpc-proxy  eu-central  4
grpc-proxy.us-east-1      grpc-proxy  us-east-1   5
grpc-proxy.us-west-2      grpc-proxy  us-west-2   4
http-proxy.eu-central     http-proxy  eu-central  2
```

**Common Use Cases**:
```bash
# List all nodes
./scripts/show/list-nodes.sh

# Show only grpc-proxy nodes
./scripts/show/list-nodes.sh --role grpc-proxy

# Show nodes in us-east-1, sorted by service count
./scripts/show/list-nodes.sh --region us-east-1 --sort-by services

# Get simple list for scripting
./scripts/show/list-nodes.sh --format simple
```

---

### `scripts/show/inspect-node.sh`

**Purpose**: Shows detailed information for a specific node, including all its services and configuration files.

**Usage**:
```bash
./scripts/show/inspect-node.sh NODE_NAME [OPTIONS]
```

**Key Features**:
- Detailed service breakdown with file status
- Optional configuration content display
- File size information
- Path information for resources

**Example Output**:
```
Node: grpc-proxy.us-east-1
=========================
Role: grpc-proxy
Region: us-east-1
Services: 5

Service Details:
┌─────────────────────────────────────┬──────────────────┬─────────────────┐
│ Service                             │ CDS File         │ EDS File        │
├─────────────────────────────────────┼──────────────────┼─────────────────┤
│ grpc-proxy.us-east-1.bar.service    │ ✓ Present (165)  │ ✓ Present (3932)│
│ grpc-proxy.us-east-1.foo.service    │ ✓ Present (165)  │ ✓ Present (3932)│
└─────────────────────────────────────┴──────────────────┴─────────────────┘
```

**Common Use Cases**:
```bash
# Basic node inspection
./scripts/show/inspect-node.sh grpc-proxy.us-east-1

# Show actual configuration content
./scripts/show/inspect-node.sh grpc-proxy.us-east-1 --show-configs

# Get JSON output for automation
./scripts/show/inspect-node.sh http-proxy.eu-central --format json
```

---

### `scripts/validate/health-check.sh`

**Purpose**: Quick validation of directory structures and configuration file formats.

**Usage**:
```bash
./scripts/validate/health-check.sh [--build-dir DIR] [--nodes-dir DIR] [OPTIONS]
```

**Key Features**:
- Directory structure validation
- JSON format validation
- Configuration consistency checks
- Performance metrics (file sizes, counts)
- Auto-detection of available structures

**Example Output**:
```
Health Check Results
===================

Directory Structure:
  ✓ nodes-and-resources/ exists
  ✓ nodes-and-resources/nodes/ exists
  ✓ nodes-and-resources/resources/ exists

File Format Validation:
  ✓ All 9 node JSON files valid
  ✓ All 20 CDS JSON files valid
  ✓ All 20 EDS JSON files valid

Configuration Consistency:
  ✓ All services have both CDS and EDS files
  ✓ All node services correspond to resource directories

Overall Health: ✓ Healthy
```

**Common Use Cases**:
```bash
# Quick health check
./scripts/validate/health-check.sh

# Detailed JSON validation
./scripts/validate/health-check.sh --json-validate

# Fast check without deep validation
./scripts/validate/health-check.sh --quick

# Check specific directory
./scripts/validate/health-check.sh --nodes-dir production-deployment
```

## Integration with Other Scripts

### Workflow Integration

**Basic Exploration Workflow**:
```bash
# 1. Get system overview
./scripts/show/summary.sh

# 2. List all nodes
./scripts/show/list-nodes.sh

# 3. Inspect specific nodes
./scripts/show/inspect-node.sh grpc-proxy.us-east-1

# 4. Validate system health
./scripts/validate/health-check.sh
```

**After Configuration Changes**:
```bash
# 1. Regenerate configurations
./scripts/generate.sh --in roles --out build

# 2. Validate and reorganize
./scripts/validate/unique-names.sh build
./scripts/sort.sh --build-dir build

# 3. Verify results
./scripts/show/summary.sh
./scripts/validate/health-check.sh
```

### Scripting Integration

The show scripts are designed for integration with automation:

**JSON Output for Processing**:
```bash
# Get node list as JSON for processing
nodes=$(./scripts/show/list-nodes.sh --format json)
echo "$nodes" | jq -r '.[] | select(.role == "grpc-proxy") | .node'
```

**Simple Output for Scripting**:
```bash
# Process each node
for node in $(./scripts/show/list-nodes.sh --format simple); do
    echo "Processing node: $node"
    ./scripts/show/inspect-node.sh "$node" --format simple
done
```

## Error Handling and Troubleshooting

### Common Issues

**Directory Not Found**:
```bash
Error: Nodes directory 'nodes-and-resources' does not exist
```
- **Solution**: Specify correct path with `--nodes-dir` or ensure you're in the right directory

**Node Not Found**:
```bash
Error: Node 'grpc-proxy.invalid' not found
Available nodes:
  grpc-proxy.us-east-1
  grpc-proxy.eu-central
```
- **Solution**: Use exact node name from the available list

**Invalid JSON Files**:
```bash
✗ Invalid JSON: /path/to/file.json
```
- **Solution**: Check file syntax with `jq '.' filename.json` and fix JSON errors

### Best Practices

1. **Always Check Summary First**:
   - Run `summary.sh` to understand what's available before using other scripts

2. **Use Filters Effectively**:
   - Filter by role or region to focus on relevant nodes/services
   - Use `--format simple` for scripting integration

3. **Validate Before Analysis**:
   - Run `health-check.sh` to ensure data integrity
   - Use `--json-validate` when troubleshooting format issues

4. **Progressive Exploration**:
   - Start with `list-nodes.sh` to see overview
   - Use `inspect-node.sh` for detailed investigation
   - Use `--show-configs` only when needed (large output)

## Output Format Standards

### Table Format
- Aligned columns with clear headers
- Unicode box drawing characters for borders
- Truncated content with "..." for long names
- Status indicators: ✓ (success), ✗ (error), ⚠ (warning)

### JSON Format
- Valid JSON suitable for `jq` processing
- Consistent field names across scripts
- Boolean values for status checks
- Array structures for lists

### Simple Format
- One item per line
- No headers or formatting
- Ideal for shell scripting and piping
- Minimal output for automation

## Future Enhancements

The show scripts framework is designed to be extensible. Planned additions include:

- Configuration content analysis scripts
- Service comparison and diff tools
- Advanced search and filtering capabilities
- Integration with monitoring and deployment tools

For implementation details and adding new scripts, refer to the main `plan.md` file.