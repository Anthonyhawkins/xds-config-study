# Configuration Management with Jsonnet

A method for organizing and configuring resources using [Jsonnet](https://jsonnet.org/) as a templating language with hierarchical variable inheritance. This is a study/proof-of-concept that demonstrates systematic approaches to configuration management across different roles, services, and regions, using XDS resources as an example domain.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Basic Concepts](#basic-concepts)
- [Project Structure](#project-structure)
- [Configuration System](#configuration-system)
- [Usage Examples](#usage-examples)
- [Advanced Workflows](#advanced-workflows)
- [Validation](#validation)
- [Scripts Reference](#scripts-reference)
- [Best Practices](#best-practices)

## Overview

This study demonstrates a systematic approach to configuration management by providing:

- **Template-driven configuration**: Use Jsonnet to generate consistent resource configurations
- **Hierarchical inheritance**: Role → Service → Profile variable cascading system
- **Multi-role support**: Different resource types with specialized defaults
- **Validation framework**: Comprehensive checks for configuration correctness
- **Automated generation**: Scripts for bulk and targeted config generation

### Configuration Management Challenges Addressed

1. **Configuration Consistency**: Ensure uniform structure across services and environments
2. **Scalability**: Manage many configurations without duplication
3. **Maintainability**: Centralized defaults with granular overrides capability
4. **Validation**: Detect configuration errors through automated checks
5. **Flexibility**: Support different configuration patterns and requirements

## Quick Start

### Prerequisites

- [Jsonnet](https://jsonnet.org/) installed (`brew install jsonnet` on macOS)
- [jq](https://stedolan.github.io/jq/) for JSON processing

### 1. Generate All Configurations

```bash
./scripts/generate.sh --in roles --out build
```

### 2. View Generated Output

```bash
# Check generated configuration files
cat build/grpc-proxy/services/foo.service/us-east-1/cds.json
cat build/grpc-proxy/services/foo.service/us-east-1/eds.json
```

### 3. Validate Configurations

```bash
# Run all validations
./scripts/validate.sh roles

# Run specific validation type
./scripts/validate/weight-distribution.sh roles
```

### 4. Generate Specific Configuration

```bash
./scripts/generate-target.sh \
  --role grpc-proxy \
  --service foo.service \
  --region us-east-1 \
  --out test-build
```

## Basic Concepts

### Configuration Templates

The system uses Jsonnet templates to generate consistent output:

- `templates/cluster.jsonnet` - Generates cluster configuration resources
- `templates/loadassignment.jsonnet` - Generates load assignment resources

These templates consume profile configurations and global variables to produce final JSON output.

#### Compound Naming Convention

Templates now generate compound names that include role, region, and service information to ensure uniqueness:

**Format**: `{role}.{region}.{service_name}`

**Examples**:
- `grpc-proxy.us-east-1.foo.service`
- `http-proxy.eu-central.api.service`
- `tcp-proxy.us-west-2.cache.service`

This naming convention ensures that configurations are unique across different roles and regions, preventing naming conflicts in multi-environment deployments.

### Resource Organization

Configurations are organized hierarchically by:
- **Role**: Different configuration types (grpc-proxy, http-proxy, tcp-proxy)
- **Service**: Individual services within each role
- **Region**: Geographic or logical deployment targets

## Project Structure

```
├── roles/                          # Role-based configurations
│   ├── grpc-proxy/                 # gRPC proxy role
│   │   ├── common.jsonnet          # Role-level defaults
│   │   └── services/
│   │       ├── foo.service/
│   │       │   ├── common.jsonnet  # Service-level overrides
│   │       │   └── us-east-1/
│   │       │       └── profile.jsonnet  # Profile-specific config
│   ├── http-proxy/                 # HTTP proxy role
│   └── tcp-proxy/                  # TCP proxy role
├── templates/                      # Jsonnet templates
│   ├── cluster.jsonnet            # CDS template
│   └── loadassignment.jsonnet     # EDS template
├── vars/                          # Global variables
│   └── endpoints.jsonnet          # Gateway endpoints
└── scripts/                       # Automation scripts
    ├── generate.sh                # Bulk generation
    ├── generate-target.sh         # Targeted generation
    ├── validate.sh                # Validation runner
    └── validate/                  # Individual validation scripts
```

## Configuration System

### Hierarchical Variable Inheritance

The system uses three levels of configuration with inheritance:

```
Role Common → Service Common → Profile Specific
```

#### 1. Role Level (`roles/{role}/common.jsonnet`)

Base defaults for all services in a role:

```jsonnet
{
  "load_balancing_method": "ROUND_ROBIN",
  "timeout": "5s",
  "regions": {
    "us-east-1": { "priority": 0, "weight": 100 },
    "us-west-2": { "priority": 1, "weight": 100 },
    "eu-central": { "priority": 2, "weight": 100 }
  }
}
```

#### 2. Service Level (`roles/{role}/services/{service}/common.jsonnet`)

Service-specific overrides:

```jsonnet
local roleCommon = import "../../common.jsonnet";

roleCommon + {
  "timeout": "3s",  // Override for faster service
  "regions": roleCommon.regions + {
    "us-east-1": roleCommon.regions["us-east-1"] + {
      "weight": 80  // Adjust weight distribution
    }
  }
}
```

#### 3. Profile Level (`profile.jsonnet`)

Final deployment-specific configuration:

```jsonnet
local serviceCommon = import "../common.jsonnet";

serviceCommon + {
  "distribution": serviceCommon.regions + {
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 0,  // Make EU primary for this deployment
      "weight": 100
    }
  }
}
```

### Role Specialization

Each role demonstrates different default patterns:

**grpc-proxy Role**
- `ROUND_ROBIN` load balancing method
- `5s` timeout value
- Multi-region distribution pattern

**http-proxy Role**  
- `LEAST_REQUEST` load balancing method
- `10s` timeout value
- Balanced regional distribution

**tcp-proxy Role**
- `ROUND_ROBIN` load balancing method
- `30s` timeout value
- Primary/standby distribution pattern

## Usage Examples

### Example 1: Basic Profile

A simple profile inheriting all defaults:

```jsonnet
// roles/grpc-proxy/services/simple.service/us-east-1/profile.jsonnet
local serviceCommon = import "../common.jsonnet";

serviceCommon + {
  "distribution": serviceCommon.regions
}
```

### Example 2: Custom Distribution

Override regional priorities and weights:

```jsonnet
local serviceCommon = import "../common.jsonnet";

serviceCommon + {
  "distribution": serviceCommon.regions + {
    "us-east-1": serviceCommon.regions["us-east-1"] + {
      "priority": 0,
      "weight": 70
    },
    "us-west-2": serviceCommon.regions["us-west-2"] + {
      "priority": 0,
      "weight": 30
    },
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 1,
      "weight": 100
    }
  }
}
```

### Example 3: Single Region Deployment

For cache or specialized services:

```jsonnet
local serviceCommon = import "../common.jsonnet";

serviceCommon + {
  "timeout": "2s",  // Fast cache timeout
  "distribution": {
    "us-west-2": {
      "priority": 0,
      "weight": 100
    }
  }
}
```

### Example 4: Database Primary/Standby

Primary database with failover:

```jsonnet
local serviceCommon = import "../common.jsonnet";

serviceCommon + {
  "timeout": "60s",  // Long timeout for DB
  "distribution": serviceCommon.regions + {
    "us-east-1": serviceCommon.regions["us-east-1"] + {
      "priority": 0,  // Primary
      "weight": 100
    },
    "eu-central": serviceCommon.regions["eu-central"] + {
      "priority": 1,  // Standby
      "weight": 100
    }
  }
}
```

## Advanced Workflows

### Bulk Configuration Management

Generate all configurations across roles:

```bash
# Generate everything
./scripts/generate.sh --in roles --out production-configs

# Generate specific role
./scripts/generate.sh --in roles/grpc-proxy --out grpc-configs
```

### Targeted Development

Work on specific services during development:

```bash
# Generate one service/region combination
./scripts/generate-target.sh \
  --role http-proxy \
  --service api.service \
  --region eu-central \
  --out dev-build

# Test the generated config
jsonnet dev-build/http-proxy/services/api.service/eu-central/eds.json | jq .
```

### Configuration Validation Pipeline

Implement validation in CI/CD:

```bash
#!/bin/bash
# validation-pipeline.sh

echo "Running configuration validation..."

# Weight distribution validation
if ! ./scripts/validate/weight-distribution.sh roles; then
  echo "❌ Weight validation failed"
  exit 1
fi

# Required fields validation  
if ! ./scripts/validate/required-fields.sh roles; then
  echo "❌ Required fields validation failed"
  exit 1
fi

# Endpoint consistency validation
if ! ./scripts/validate/endpoint-consistency.sh roles; then
  echo "❌ Endpoint consistency validation failed"
  exit 1
fi

echo "✅ All validations passed"

# Generate production configs
./scripts/generate.sh --in roles --out production-build

echo "🚀 Production configs generated"
```

### Testing Configuration Changes

Compare configurations before and after changes:

```bash
# Before changes
./scripts/generate.sh --in roles --out before-configs

# Make your changes...
# edit roles/grpc-proxy/services/foo.service/common.jsonnet

# After changes  
./scripts/generate.sh --in roles --out after-configs

# Compare
diff -r before-configs after-configs
```

## Validation

The project includes comprehensive validation to catch configuration errors:

### Weight Distribution Validation

Ensures weights in each priority group sum to exactly 100:

```bash
./scripts/validate/weight-distribution.sh roles
```

**Common Issues:**
- Priority 0 regions: us-east-1 (80) + us-west-2 (30) = 110 ❌
- Should be: us-east-1 (70) + us-west-2 (30) = 100 ✅

### Required Fields Validation

Checks for required fields and valid data types:

```bash
./scripts/validate/required-fields.sh roles
```

**Validates:**
- Required fields: `load_balancing_method`, `timeout`, `distribution`
- Timeout format: `"3s"`, `"500ms"` ✅ vs `"3seconds"` ❌
- Load balancing methods: `ROUND_ROBIN`, `LEAST_REQUEST`, etc.
- Priority/weight data types: integers ✅ vs strings ❌

### Endpoint Consistency Validation

Verifies profile regions exist in endpoints configuration:

```bash
./scripts/validate/endpoint-consistency.sh roles
```

**Checks:**
- All distribution regions exist in `vars/endpoints.jsonnet`
- Valid IP addresses (IPv4 format)
- Valid port ranges (1-65535)
- No duplicate IP addresses across regions (warning)

### Unique Names Validation

Ensures generated configuration names are unique to prevent conflicts:

```bash
# First generate configurations
./scripts/generate.sh --in roles --out build

# Then validate unique names
./scripts/validate/unique-names.sh build
```

**Validates:**
- CDS files: `name` field must be unique across all `cds.json` files
- EDS files: `cluster_name` field must be unique across all `eds.json` files
- Detects and reports duplicate names with file locations

**Example Output:**
```
✓ All 20 CDS names are unique
✓ All 20 EDS cluster_names are unique
```

**Error Example:**
```
ERROR: Duplicate CDS name 'grpc-proxy.us-east-1.foo.service' found in files:
  - grpc-proxy/services/bar.service/us-east-1/cds.json
  - grpc-proxy/services/foo.service/us-east-1/cds.json
```

### Running All Validations

```bash
# Run all validations together (source validations only)
./scripts/validate.sh roles

# Run specific validation only
./scripts/validate.sh --weight-only roles
./scripts/validate.sh --fields-only roles
./scripts/validate.sh --endpoints-only roles
./scripts/validate.sh --names-only roles  # Shows instructions for unique names validation
```

**Note**: Unique names validation requires generated configuration files and must be run separately:

```bash
# Generate configurations first
./scripts/generate.sh --in roles --out build

# Then run unique names validation
./scripts/validate/unique-names.sh build
```

## Scripts Reference

This section provides comprehensive documentation for all automation scripts, their purpose, usage patterns, and example workflows.

### Generation Scripts

#### `scripts/generate.sh` - Bulk Configuration Generation

**Purpose**: Generate configurations for all profiles within a directory tree, creating a mirrored output structure containing only the generated JSON files.

**Usage**:
```bash
./scripts/generate.sh --in INPUT_DIR --out OUTPUT_DIR
```

**Parameters**:
- `--in INPUT_DIR`: Directory containing role-based profile configurations
- `--out OUTPUT_DIR`: Output directory where generated configs will be placed

**Examples**:

```bash
# Generate all configurations
./scripts/generate.sh --in roles --out build
# Result: build/ contains complete mirror with only .json files

# Generate configs for specific role
./scripts/generate.sh --in roles/grpc-proxy --out grpc-only
# Result: grpc-only/ contains only grpc-proxy configurations

# Generate from custom input directory
./scripts/generate.sh --in custom-roles --out custom-build
# Result: custom-build/ contains configs from custom profile definitions

# Verify generation process
./scripts/generate.sh --in roles --out test-build && echo "Generation successful"
```

**Output Structure**:
```
build/
├── grpc-proxy/
│   └── services/
│       ├── foo.service/
│       │   └── us-east-1/
│       │       ├── cds.json
│       │       └── eds.json
│       └── bar.service/
│           └── eu-central/
│               ├── cds.json
│               └── eds.json
├── http-proxy/
└── tcp-proxy/
```

#### `scripts/generate-target.sh` - Targeted Configuration Generation

**Purpose**: Generate configurations for a specific role/service/region combination, useful for testing individual configurations.

**Usage**:
```bash
./scripts/generate-target.sh --role ROLE --service SERVICE --region REGION --out OUTPUT_DIR
```

**Parameters**:
- `--role ROLE`: Configuration role (grpc-proxy, http-proxy, tcp-proxy)
- `--service SERVICE`: Service name (foo.service, api.service, etc.)
- `--region REGION`: Region name (us-east-1, eu-central, us-west-2)
- `--out OUTPUT_DIR`: Output directory for generated files

**Examples**:

```bash
# Generate specific service configuration
./scripts/generate-target.sh \
  --role grpc-proxy \
  --service foo.service \
  --region us-east-1 \
  --out test-output

# Inspect generated configuration
cat test-output/grpc-proxy/services/foo.service/us-east-1/eds.json | jq .

# Generate configuration for different role
./scripts/generate-target.sh \
  --role http-proxy \
  --service api.service \
  --region eu-central \
  --out api-test

# Generate multiple regions for same service
for region in us-east-1 us-west-2 eu-central; do
  ./scripts/generate-target.sh \
    --role grpc-proxy \
    --service test.service \
    --region $region \
    --out output-$region
  
  echo "Generated config for $region"
done
```

**Error Handling**:
```bash
# Script validates inputs and provides helpful error messages
./scripts/generate-target.sh --role invalid-role --service test --region us-east-1 --out test
# Output: Error: Role 'invalid-role' not found
#         Available roles: grpc-proxy, http-proxy, tcp-proxy

./scripts/generate-target.sh --role grpc-proxy --service missing --region us-east-1 --out test  
# Output: Error: Service 'missing' not found in role 'grpc-proxy'
#         Available services: foo.service, bar.service, baz.service, ...
```

### Validation Scripts

#### `scripts/validate.sh` - Comprehensive Validation Runner

**Purpose**: Execute all validation checks or specific validation types across configuration profiles to ensure correctness.

**Usage**:
```bash
./scripts/validate.sh [OPTIONS] INPUT_DIR
```

**Options**:
- `--weight-only`: Run only weight distribution validation
- `--fields-only`: Run only required fields validation  
- `--endpoints-only`: Run only endpoint consistency validation
- `--names-only`: Show instructions for unique names validation
- (no option): Run all validations

**Examples**:

```bash
# Run all validations
./scripts/validate.sh roles
# Exit code 0 = success, 1 = validation failed

# Run specific validation type
./scripts/validate.sh --weight-only roles
./scripts/validate.sh --fields-only roles
./scripts/validate.sh --endpoints-only roles
./scripts/validate.sh --names-only roles

# Validate specific role subset
./scripts/validate.sh roles/grpc-proxy

# Save validation results
./scripts/validate.sh roles > validation-report.txt 2>&1
```

#### `scripts/validate/weight-distribution.sh` - Weight Distribution Validator

**Purpose**: Ensure that load balancing weights within each priority group sum to exactly 100.

**Usage**:
```bash
./scripts/validate/weight-distribution.sh INPUT_DIR
```

**Examples**:

```bash
# Validate all weight distributions
./scripts/validate/weight-distribution.sh roles

# Validate specific service
./scripts/validate/weight-distribution.sh roles/grpc-proxy/services/foo.service

# Filter for weight errors only
./scripts/validate/weight-distribution.sh roles | grep "weight sum"
```

**Sample Output**:
```
❌ [foo.service/us-east-1] Priority 0: weight sum is 110, expected 100 (regions: us-east-1,us-west-2)
✅ [bar.service/eu-central] Weight distribution valid
```

#### `scripts/validate/required-fields.sh` - Field Requirements Validator

**Purpose**: Verify that all required fields are present with correct data types and validate field value formats.

**Usage**:
```bash
./scripts/validate/required-fields.sh INPUT_DIR
```

**Examples**:

```bash
# Validate all required fields
./scripts/validate/required-fields.sh roles

# Validate specific service
./scripts/validate/required-fields.sh roles/http-proxy/services/api.service

# Check for specific issues
./scripts/validate/required-fields.sh roles | grep timeout
./scripts/validate/required-fields.sh roles | grep "Missing required field"
```

**Sample Output**:
```
✅ [api.service/us-east-1] Required fields valid
❌ [broken.service/eu-central] Missing required field: timeout
⚠️  [slow.service/us-west-2] Invalid timeout format: '3seconds' (expected: '3s' or '500ms')
⚠️  [custom.service/us-east-1] Unknown load balancing method: 'CUSTOM_LB'
```

#### `scripts/validate/endpoint-consistency.sh` - Endpoint Consistency Validator

**Purpose**: Verify that all regions referenced in profile distributions exist in the global endpoints configuration and validate endpoint data integrity.

**Usage**:
```bash
./scripts/validate/endpoint-consistency.sh INPUT_DIR
```

**Examples**:

```bash
# Validate all endpoint consistency
./scripts/validate/endpoint-consistency.sh roles

# Check for IP address conflicts
./scripts/validate/endpoint-consistency.sh roles | grep "duplicate"

# Save endpoint validation results
./scripts/validate/endpoint-consistency.sh roles > endpoint-report.txt
```

**Sample Output**:
```
✅ Global endpoint consistency checked
❌ [service.foo/us-east-1] Region 'ap-south-1' in distribution not found in endpoints.jsonnet
❌ [service.bar/eu-central] Invalid IP address '300.1.2.3' in region 'eu-central'
⚠️  IP address '10.1.2.3' used in multiple regions: us-east-1, us-west-2
✅ [service.baz/us-west-2] Endpoint consistency valid
```

#### `scripts/validate/unique-names.sh` - Unique Names Validator

**Purpose**: Ensure that generated configuration names are unique to prevent conflicts in deployment environments.

**Usage**:
```bash
./scripts/validate/unique-names.sh BUILD_DIR
```

**Parameters**:
- `BUILD_DIR`: Directory containing generated configuration files (output from generate.sh)

**Examples**:

```bash
# Validate unique names after generation
./scripts/generate.sh --in roles --out build
./scripts/validate/unique-names.sh build

# Validate specific subset
./scripts/generate.sh --in roles/grpc-proxy --out grpc-build
./scripts/validate/unique-names.sh grpc-build

# Save unique names validation results
./scripts/validate/unique-names.sh build > unique-names-report.txt
```

**Sample Output**:
```
✓ All 20 CDS names are unique
✓ All 20 EDS cluster_names are unique
All unique name validations passed!
```

**Error Output**:
```
ERROR: Duplicate CDS name 'grpc-proxy.us-east-1.foo.service' found in files:
  - grpc-proxy/services/bar.service/us-east-1/cds.json
  - grpc-proxy/services/foo.service/us-east-1/cds.json
ERROR: Duplicate EDS cluster_name 'http-proxy.eu-central.api.service' found in files:
  - http-proxy/services/api.service/eu-central/eds.json
  - http-proxy/services/web.service/eu-central/eds.json
Found 2 unique name validation errors
```

## Best Practices

### Configuration Design

1. **Use Inheritance Effectively**
   - Put common settings in role-level configs
   - Override only what changes at service level
   - Minimize profile-specific overrides

2. **Weight Distribution**
   - Always ensure weights per priority sum to 100
   - Use meaningful weight ratios (70/30, not 71/29)
   - Consider network capacity when setting weights

3. **Timeout Strategy**
   - Fast services: 2-5s timeouts
   - Standard services: 5-10s timeouts  
   - Long-running operations: 30-60s timeouts

4. **Regional Strategy**
   - Primary regions: Priority 0, higher weights
   - Failover regions: Priority 1+, balanced weights
   - Backup regions: Higher priorities for redundancy

5. **Naming Convention**
   - Compound names automatically ensure uniqueness across roles and regions
   - Format: `{role}.{region}.{service_name}` (e.g., `grpc-proxy.us-east-1.foo.service`)
   - Use the unique names validation to verify no conflicts in generated configurations
   - Avoid manual name customization that could break the compound naming pattern

### Development Workflow

1. **Start Small**
   ```bash
   # Create a simple profile first
   ./scripts/generate-target.sh --role grpc-proxy --service test.service --region us-east-1 --out test
   ```

2. **Validate Early**
   ```bash
   # Validate source configurations after every change
   ./scripts/validate.sh roles
   
   # Generate and validate unique names
   ./scripts/generate.sh --in roles --out build
   ./scripts/validate/unique-names.sh build
   ```

3. **Use Version Control**
   ```bash
   # Track configuration changes
   git add roles/
   git commit -m "Update service configuration"
   ```

4. **Test Incrementally**
   ```bash
   # Generate and test one service at a time
   ./scripts/generate-target.sh --role http-proxy --service api.service --region us-east-1 --out test-api
   # Review generated configuration
   # Then generate full build
   ```

### Configuration Maintenance

1. **Regular Validation**
   - Run source validations after configuration changes: `./scripts/validate.sh roles`
   - Generate and validate unique names: `./scripts/validate/unique-names.sh build`
   - Use automated validation in CI/CD workflows
   - Monitor configuration consistency across environments

2. **Documentation**
   - Comment complex configurations
   - Document configuration patterns
   - Maintain change logs for updates

3. **Performance Considerations**
   - Monitor jsonnet compilation times for large configs
   - Use `--jpath` efficiently in templates
   - Consider optimization for large configuration sets

---

This study demonstrates a systematic method for organizing and configuring resources using Jsonnet. The hierarchical inheritance system, compound naming convention for uniqueness, comprehensive validation (including unique names validation), and automation scripts provide a foundation for maintaining consistent, correct configurations across complex multi-role, multi-service deployments.