# SARIF ABI Contract v0.5 Integrity Baseline

## Overview

The Parrot MCP Server implements a hardened SARIF (Static Analysis Results Interchange Format) ABI Contract that ensures stable, reproducible, and auditable security analysis outputs. This implementation follows the SARIF 2.1.0 specification with additional integrity guarantees.

## Architecture

### Components

1. **Rule Registry** (`scripts/sarif_rules_registry.sh`)
   - Central registry of stable rule identifiers
   - Semantic versioning for each rule (MAJOR.MINOR.PATCH)
   - Rule Change Impact Analysis (RCIA) tracking
   - Opaque rule IDs that remain stable across code changes

2. **SARIF Generator** (`scripts/sarif_generator.sh`)
   - Generates SARIF 2.1.0 compliant output
   - Implements deterministic fingerprinting
   - Adds comprehensive provenance metadata
   - Supports URI canonicalization with uriBaseId

3. **SARIF Scanner** (`scripts/sarif_scanner.sh`)
   - Static analysis of shell scripts
   - Security, quality, and performance rule checking
   - Deterministic output ordering
   - Stable partial fingerprints

4. **SARIF Validator** (`scripts/sarif_validator.sh`)
   - SARIF 2.1.0 schema validation
   - Consistency checking
   - Environmental issue detection
   - File size and optimization warnings

## Features

### 1. Rule Identifier Stability

**Opaque Rule IDs**: Rules are identified by stable IDs (e.g., SEC001, QUAL002) that don't change when implementation logic is updated.

**Semantic Versioning**: Each rule has a version following MAJOR.MINOR.PATCH:
- MAJOR: Breaking changes to rule logic or findings
- MINOR: New detection capabilities that don't affect existing findings
- PATCH: Bug fixes that improve accuracy

**Rule Change Impact Analysis (RCIA)**: All rule changes are logged with timestamps and version bumps.

Example:
```bash
./scripts/sarif_rules_registry.sh list
# Output shows:
# SEC001     v1.0.0    [security    ] Hardcoded credentials detected
# SEC002     v1.0.0    [security    ] Insecure random number generation
```

### 2. File Determinism Rules

**Deterministic Sorting**: Results are sorted by:
1. Rule ID (alphabetically)
2. File URI (alphabetically)
3. Start line number (numerically)

**Relative URI Paths**: All artifact locations use relative paths with `uriBaseId: "%SRCROOT%"` for portability.

**Stable Fingerprints**: Partial fingerprints are generated using:
```
SHA-256(ruleId:uri:startLine:startColumn)
```

This ensures findings remain stable across:
- Different machines
- Different branches
- Incremental code changes (as long as line numbers don't shift)

### 3. Provenance Metadata

Every SARIF output includes:

**Tool Information**:
- Exact tool version (semantic versioning)
- Tool checksum for integrity verification
- Information URI for documentation

**Version Control Details**:
- Repository URI
- Exact commit SHA
- Branch name
- Git tags (if applicable)

**Chain of Custody**:
- Analysis timestamp (UTC)
- Host architecture and OS
- Generator version and checksum
- Policy integrity checksums (SHA-256)

Example output:
```json
{
  "runs": [{
    "tool": {
      "driver": {
        "name": "Parrot MCP Server",
        "version": "0.5.0",
        "semanticVersion": "0.5.0",
        "properties": {
          "ruleRegistryVersion": "1.0.0",
          "abiContractVersion": "0.5.0",
          "integrityBaseline": "v0.5",
          "policyChecksum": "31a569945c50d9276ea25009808531d160228c269c63fc7596b6f9a5d4f69a53"
        }
      }
    },
    "versionControlProvenance": [{
      "repositoryUri": "https://github.com/canstralian/parrot_mcp_server",
      "revisionId": "a4625748c8e4e24a5b4d3f3d91d1d68320cb87be",
      "branch": "copilot/implement-sarif-abi-contract"
    }],
    "properties": {
      "analysisTimestamp": "2025-11-11T12:36:19Z",
      "hostArchitecture": "x86_64",
      "hostOS": "Linux",
      "chainOfCustody": {
        "generatorVersion": "0.5.0",
        "generatorChecksum": "a05c9c0b8e3ed3a903df2d356b63097fee47653d2bccdd41b1ab5a888c6f637c"
      }
    }
  }]
}
```

### 4. Validation Pipelines

**Schema Validation**: Validates against official SARIF 2.1.0 JSON schema.

**Required Fields Check**: Ensures all mandatory SARIF fields are present.

**Consistency Checks**: Verifies that:
- All referenced rules are defined
- Results reference valid rules
- Partial fingerprints are present
- URIs are properly canonicalized

**Warning Systems**:
- File size warnings for large outputs
- Missing optional but recommended fields
- Absolute paths in URIs
- Unsorted results

Example:
```bash
./scripts/sarif_validator.sh validate output.sarif
# Runs comprehensive validation with detailed report
```

### 5. Test Infrastructure

**Integration Tests**: Comprehensive test suite using BATS framework (`tests/sarif_integration.bats`).

**Test Coverage**:
- Rule registry operations
- SARIF generation
- Fingerprint stability
- Validation checks
- Scanner accuracy
- End-to-end workflows

**Golden Output Protocol**: Tests verify deterministic output by comparing:
- Fingerprints across runs
- Sorting consistency
- Metadata completeness

## Usage

### CLI Integration

All SARIF tools are available through the main CLI:

```bash
# List available rules
./cli.sh sarif_rules_registry list

# Scan a directory
./cli.sh sarif_scanner scan ./scripts output.sarif

# Validate SARIF output
./cli.sh sarif_validator validate output.sarif

# Generate empty SARIF report
./cli.sh sarif_generator generate output.sarif
```

### Scanning Scripts

```bash
# Scan a single file
./scripts/sarif_scanner.sh file myScript.sh output.sarif

# Scan a directory
./scripts/sarif_scanner.sh scan ./my-scripts output.sarif "*.sh"

# View findings
jq '.runs[0].results[] | {ruleId, message: .message.text, file: .locations[0].physicalLocation.artifactLocation.uri, line: .locations[0].physicalLocation.region.startLine}' output.sarif
```

### Rule Management

```bash
# List all rules
./scripts/sarif_rules_registry.sh list

# Get rule information
./scripts/sarif_rules_registry.sh get SEC001

# Check rule version
./scripts/sarif_rules_registry.sh version SEC001

# View change log
./scripts/sarif_rules_registry.sh changelog SEC001
```

### Validation

```bash
# Comprehensive validation
./scripts/sarif_validator.sh validate output.sarif

# Quick syntax check
./scripts/sarif_validator.sh syntax output.sarif

# Schema validation only (requires ajv-cli)
./scripts/sarif_validator.sh schema output.sarif
```

## Supported Rules

### Security Rules

- **SEC001**: Hardcoded credentials detected
- **SEC002**: Insecure random number generation
- **SEC003**: Command injection vulnerability
- **SEC004**: Path traversal vulnerability
- **SEC005**: Insufficient input validation

### Quality Rules

- **QUAL001**: Code complexity exceeds threshold
- **QUAL002**: Duplicated code block detected
- **QUAL003**: Missing error handling

### Performance Rules

- **PERF001**: Inefficient algorithm usage
- **PERF002**: Excessive resource allocation

## Extending the System

### Adding New Rules

1. Add rule to `SARIF_RULES` array in `sarif_rules_registry.sh`:
```bash
["SEC006"]="1.0.0:SQL injection vulnerability:security"
```

2. Add change log entry:
```bash
["SEC006"]="1.0.0:2025-11-11:Initial implementation"
```

3. Implement detection in `sarif_scanner.sh`:
```bash
if [[ "$line" =~ mysql.*\$[A-Za-z_]+ ]]; then
    add_finding "SEC006" "$file" "$line_num" "Potential SQL injection" "error"
fi
```

### Updating Rule Logic

When updating rule logic:

1. Assess impact on existing findings
2. Update version following SemVer:
   - MAJOR: Changes what findings are reported
   - MINOR: Adds new detection patterns
   - PATCH: Fixes false positives/negatives
3. Update change log with date and description
4. Update `SARIF_RULES` array with new version

## Integration with CI/CD

```bash
#!/usr/bin/env bash
# Example CI script

# Scan codebase
./rpi-scripts/scripts/sarif_scanner.sh scan ./src output.sarif

# Validate output
./rpi-scripts/scripts/sarif_validator.sh validate output.sarif

# Upload to analysis platform
# (GitHub Code Scanning, GitLab SAST, etc.)
curl -X POST \
  -H "Content-Type: application/sarif+json" \
  -d @output.sarif \
  "https://api.example.com/analysis"
```

## Compliance and Standards

- **SARIF 2.1.0**: Full compliance with OASIS SARIF specification
- **JSON Schema**: Validates against official schema
- **Deterministic Output**: Ensures reproducible results
- **Provenance Tracking**: Complete chain of custody for audit trails
- **Semantic Versioning**: Rule versions follow SemVer 2.0.0

## Troubleshooting

### Validation Failures

**Issue**: "Invalid JSON syntax"
- **Solution**: Use `jq` to pretty-print and identify syntax errors

**Issue**: "Schema validation failed"
- **Solution**: Install ajv-cli: `npm install -g ajv-cli`

**Issue**: "Missing required fields"
- **Solution**: Ensure SARIF was generated with latest version of generator

### Scanner Issues

**Issue**: "No issues found"
- **Solution**: Check that file pattern matches target files
- **Solution**: Verify rules are appropriate for the code being scanned

**Issue**: "Too many false positives"
- **Solution**: Review rule definitions and adjust detection patterns
- **Solution**: Use rule version to track when logic was last updated

## References

- [SARIF 2.1.0 Specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
- [SARIF Tutorials](https://github.com/microsoft/sarif-tutorials)
- [GitHub Code Scanning](https://docs.github.com/en/code-security/code-scanning)
