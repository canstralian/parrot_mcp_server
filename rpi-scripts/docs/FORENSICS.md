# Forensics Integration Guide

This guide covers the memory and disk forensics capabilities integrated into the Parrot MCP Server.

## Overview

The Parrot MCP Server now includes comprehensive forensics analysis capabilities through Bash wrapper scripts that integrate with industry-standard tools:

- **Memory Forensics**: Volatility 3 integration for analyzing memory dumps
- **Disk Forensics**: SleuthKit integration for analyzing disk images

## Architecture

The forensics integration follows the repository's Bash-first philosophy:

- **Common Utilities** (`forensics_common.sh`): Shared functions for dependency checking, result management, caching, and reporting
- **Memory Forensics** (`memory_forensics.sh`): Volatility 3 wrapper for memory analysis
- **Disk Forensics** (`disk_forensics.sh`): SleuthKit wrapper for disk analysis

All scripts are accessible via the CLI tool (`cli.sh`) and follow the same patterns as other repository scripts.

## Installation

### Prerequisites

#### Python 3 and pip
```bash
sudo apt-get update
sudo apt-get install python3 python3-pip
```

#### Volatility 3 (for Memory Forensics)
```bash
pip3 install volatility3
```

Or from source:
```bash
git clone https://github.com/volatilityfoundation/volatility3.git
cd volatility3
pip3 install -r requirements.txt
python3 setup.py install
```

#### SleuthKit (for Disk Forensics)
```bash
sudo apt-get install sleuthkit
```

#### Optional: Python Bindings for Advanced Features
```bash
# For programmatic SleuthKit access
pip3 install pytsk3

# For PE file analysis
pip3 install pefile

# For YARA rules in malware detection
pip3 install yara-python
```

### Verify Installation

Check if dependencies are installed:

```bash
# Check memory forensics dependencies
./cli.sh memory_forensics --check

# Check disk forensics dependencies
./cli.sh disk_forensics --check
```

## Memory Forensics

### Overview

Memory forensics analyzes RAM dumps to extract:
- Running processes and their relationships
- Network connections
- Malware indicators
- Registry data
- File handles and DLLs

### Supported Memory Dump Formats

- Raw memory dumps (`.raw`, `.mem`, `.dump`)
- VMware memory files (`.vmem`)
- VirtualBox core dumps
- ELF core dumps
- Windows crash dumps

### Available Plugins

**Process Analysis:**
- `pslist` - List running processes
- `pstree` - Display process tree
- `psscan` - Scan for EPROCESS structures
- `psxview` - Cross-reference process listings
- `cmdline` - Display command-line arguments

**Network Analysis:**
- `netscan` - Scan for network connections
- `netstat` - Network statistics

**Malware Detection:**
- `malfind` - Find malicious code patterns
- `apihooks` - Detect API hooks
- `ldrmodules` - Detect unlinked DLLs

**File Analysis:**
- `filescan` - Scan for file objects
- `dumpfiles` - Extract files from memory
- `handles` - List open handles

**Registry Analysis:**
- `hivelist` - List registry hives
- `printkey` - Print registry key values

### Usage Examples

#### Basic Analysis

Analyze a memory dump with default plugins:
```bash
./cli.sh memory_forensics -d /path/to/memory.dump
```

#### Run Specific Plugins

Execute multiple plugins on a memory dump:
```bash
./cli.sh memory_forensics -d /path/to/memory.dump -p "pslist,netscan,malfind"
```

#### List Available Plugins

```bash
./cli.sh memory_forensics --list-plugins
```

#### Check Dependencies

```bash
./cli.sh memory_forensics --check
```

### Output Structure

Each analysis creates a unique result directory:
```
forensics/results/memory_YYYYMMDD_HHMMSS_PID/
├── metadata.json          # Analysis metadata
├── pslist.txt            # Process list output
├── netscan.txt           # Network connections
├── malfind.txt           # Malware findings
├── iocs.json             # Extracted IOCs
├── timeline.csv          # Event timeline
└── summary.txt           # Analysis summary
```

### IOC Extraction

The tool automatically extracts Indicators of Compromise (IOCs):
- IP addresses from network connections
- Suspicious process patterns
- File paths
- Registry keys

Results are saved in `iocs.json` for further analysis.

### Caching

Results are cached to avoid reprocessing:
- Cache key is generated from dump hash + plugin name
- Cache expires after 24 hours
- Cached results are used for repeated analyses

## Disk Forensics

### Overview

Disk forensics analyzes disk images to:
- Generate filesystem timelines
- Recover deleted files
- Compute file hashes
- Search for strings and patterns
- Extract metadata

### Supported Disk Image Formats

- Raw disk images (`.dd`, `.raw`, `.img`)
- E01 (EnCase) format
- AFF (Advanced Forensic Format)
- Split images

### Available Operations

- `timeline` - Generate filesystem timeline
- `info` - Get filesystem information
- `list` - List all files
- `deleted` - List deleted files
- `hashes` - Compute file hashes
- `search` - Search for strings in image

### Usage Examples

#### Generate Timeline

Create a filesystem timeline:
```bash
./cli.sh disk_forensics -i /path/to/disk.dd -o timeline
```

#### List Files

List all files in the disk image:
```bash
./cli.sh disk_forensics -i /path/to/disk.dd -o list
```

#### Find Deleted Files

List deleted file entries:
```bash
./cli.sh disk_forensics -i /path/to/disk.dd -o deleted
```

#### Search for Strings

Search for specific strings in the disk image:
```bash
./cli.sh disk_forensics -i /path/to/disk.dd -o search -s "password"
```

#### Get Filesystem Info

Display partition and filesystem information:
```bash
./cli.sh disk_forensics -i /path/to/disk.dd -o info
```

#### Compute Hashes

Generate hash values for files:
```bash
./cli.sh disk_forensics -i /path/to/disk.dd -o hashes
```

### Output Structure

Each analysis creates a unique result directory:
```
forensics/results/disk_YYYYMMDD_HHMMSS_PID/
├── metadata.json              # Analysis metadata
├── timeline.csv               # Filesystem timeline
├── file_list.txt             # All files
├── deleted_files.txt         # Deleted file entries
├── file_hashes.csv           # File hash values
├── search_results.txt        # String search results
├── filesystem_info.txt       # FS information
└── summary.txt               # Analysis summary
```

## Common Features

### Progress Reporting

Long-running operations report progress:
```
[INFO] Memory Analysis (45%): Processing plugin 3/7: malfind
[INFO] Timeline Generation (30%): Extracting file metadata
```

### Result Management

- **Unique Analysis IDs**: Each analysis gets a unique ID based on timestamp and PID
- **Metadata Tracking**: All analyses include metadata (hash, size, timestamp)
- **Organized Results**: Results are organized in timestamped directories

### Caching System

- Cache keys based on file hash and operation
- 24-hour cache expiration
- Automatic cache reuse for identical operations
- Cache stored in `forensics/cache/`

### Hash Computation

Multiple hash algorithms supported:
- MD5
- SHA1
- SHA256 (default)

### Error Handling

Scripts handle errors gracefully:
- Validate input files before processing
- Check dependencies on startup
- Provide helpful error messages
- Continue with remaining operations if one fails

## Integration with MCP Server

### Future API Endpoints

The forensics scripts are designed to be integrated with the MCP server via future API endpoints:

```
# Memory Forensics
POST /api/forensics/memory/analyze
POST /api/forensics/memory/plugin/{plugin_name}
GET  /api/forensics/memory/{analysis_id}/results
GET  /api/forensics/memory/{analysis_id}/iocs

# Disk Forensics
POST /api/forensics/disk/mount
POST /api/forensics/disk/timeline
POST /api/forensics/disk/search
POST /api/forensics/disk/carve
GET  /api/forensics/disk/{analysis_id}/files
```

### Current CLI Integration

All forensics operations are available through the CLI:

```bash
# Direct script execution
bash scripts/memory_forensics.sh -d dump.mem -p pslist,netscan

# Via CLI wrapper
./cli.sh memory_forensics -d dump.mem -p pslist,netscan
```

## Performance Considerations

### Memory Dumps

- **Large Files**: Memory dumps can be 8GB or larger
- **Processing Time**: Full analysis can take 15-30 minutes per plugin
- **Parallel Execution**: Future versions will support parallel plugin execution
- **Caching**: Use caching to avoid reprocessing

### Disk Images

- **Timeline Generation**: Can take 10-30 minutes for large disks
- **String Search**: Very slow on large images, consider targeted searches
- **Hash Computation**: Sample-based approach for large image files

### Optimization Tips

1. **Use caching**: Repeated analyses use cached results
2. **Select specific plugins**: Don't run all plugins if not needed
3. **Filter searches**: Use targeted string searches instead of broad searches
4. **Consider disk space**: Results and cache can consume significant space

## Troubleshooting

### Common Issues

#### Volatility Not Found

```bash
# Install Volatility 3
pip3 install volatility3

# Or check if it's installed as module
python3 -m volatility3.cli --help
```

#### SleuthKit Not Found

```bash
# Install SleuthKit
sudo apt-get update
sudo apt-get install sleuthkit

# Verify installation
fls -V
```

#### Permission Denied

Ensure forensics directories are writable:
```bash
chmod -R u+w forensics/
```

#### Out of Disk Space

Clean old results and cache:
```bash
rm -rf forensics/results/*
rm -rf forensics/cache/*
```

### Debug Mode

Enable verbose logging by setting environment variables:
```bash
export PARROT_LOG_LEVEL="DEBUG"
export PARROT_DEBUG="true"

./cli.sh memory_forensics -d dump.mem -p pslist
```

## Best Practices

### Evidence Handling

1. **Hash First**: Always compute hash of original evidence
2. **Work on Copies**: Never analyze original evidence
3. **Document Chain of Custody**: Keep detailed logs
4. **Verify Integrity**: Check hashes before and after analysis

### Analysis Workflow

1. **Start Broad**: Use overview plugins first (pslist, netscan)
2. **Identify Suspicious**: Look for anomalies in initial results
3. **Deep Dive**: Use targeted plugins for suspicious items
4. **Correlate**: Cross-reference findings across different plugins
5. **Document**: Save all findings with context

### Security

1. **Isolate Analysis Environment**: Analyze malware in isolated VM
2. **Validate Input**: Always validate input files
3. **Sanitize Output**: Be careful with extracted artifacts
4. **Secure Storage**: Encrypt forensics results at rest

## Examples

### Complete Memory Analysis Workflow

```bash
# 1. Check dependencies
./cli.sh memory_forensics --check

# 2. Initial triage
./cli.sh memory_forensics -d suspect.mem -p "pslist,pstree,netscan"

# 3. Malware analysis
./cli.sh memory_forensics -d suspect.mem -p "malfind,apihooks,ldrmodules"

# 4. File system analysis
./cli.sh memory_forensics -d suspect.mem -p "filescan,handles"

# 5. Registry analysis
./cli.sh memory_forensics -d suspect.mem -p "hivelist,printkey"

# 6. Review results
ls -l forensics/results/memory_*/
cat forensics/results/memory_*/iocs.json
```

### Complete Disk Analysis Workflow

```bash
# 1. Check dependencies
./cli.sh disk_forensics --check

# 2. Get filesystem info
./cli.sh disk_forensics -i evidence.dd -o info

# 3. Generate timeline
./cli.sh disk_forensics -i evidence.dd -o timeline

# 4. List all files
./cli.sh disk_forensics -i evidence.dd -o list

# 5. Find deleted files
./cli.sh disk_forensics -i evidence.dd -o deleted

# 6. Search for keywords
./cli.sh disk_forensics -i evidence.dd -o search -s "confidential"

# 7. Compute hashes
./cli.sh disk_forensics -i evidence.dd -o hashes

# 8. Review results
ls -l forensics/results/disk_*/
cat forensics/results/disk_*/summary.txt
```

## Contributing

To contribute forensics features:

1. Follow the Bash-first philosophy
2. Use common utility functions from `forensics_common.sh`
3. Add tests in `tests/forensics.bats`
4. Document new features in this guide
5. Ensure shellcheck passes

## References

- [Volatility 3 Documentation](https://volatility3.readthedocs.io/)
- [SleuthKit Documentation](https://www.sleuthkit.org/sleuthkit/docs.php)
- [The Art of Memory Forensics](https://www.memoryanalysis.net/)
- [File System Forensic Analysis](https://www.sleuthkit.org/books.php)

## License

This forensics integration is part of the Parrot MCP Server project and follows the same MIT license.
