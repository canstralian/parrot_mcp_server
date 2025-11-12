# Forensics Quick Start Guide

Quick reference for using the Parrot MCP Server forensics capabilities.

## Installation

### Install Volatility 3 (Memory Forensics)
```bash
pip3 install volatility3
```

### Install SleuthKit (Disk Forensics)
```bash
sudo apt-get install sleuthkit
```

### Verify Installation
```bash
./cli.sh memory_forensics --check
./cli.sh disk_forensics --check
```

## Memory Forensics

### Quick Commands

```bash
# List available plugins
./cli.sh memory_forensics --list-plugins

# Basic memory analysis (default plugins)
./cli.sh memory_forensics -d memory.dump

# Run specific plugins
./cli.sh memory_forensics -d memory.dump -p "pslist,netscan,malfind"

# Full malware analysis
./cli.sh memory_forensics -d memory.dump -p "pslist,pstree,netscan,malfind,apihooks,ldrmodules"
```

### Common Plugin Combinations

**Initial Triage:**
```bash
./cli.sh memory_forensics -d memory.dump -p "pslist,pstree,netscan"
```

**Malware Hunt:**
```bash
./cli.sh memory_forensics -d memory.dump -p "malfind,apihooks,ldrmodules,handles"
```

**Network Investigation:**
```bash
./cli.sh memory_forensics -d memory.dump -p "netscan,netstat"
```

**File System Analysis:**
```bash
./cli.sh memory_forensics -d memory.dump -p "filescan,handles,dlllist"
```

**Registry Analysis:**
```bash
./cli.sh memory_forensics -d memory.dump -p "hivelist,printkey"
```

### Output Location
Results are saved in `forensics/results/memory_TIMESTAMP/`

## Disk Forensics

### Quick Commands

```bash
# Get filesystem info
./cli.sh disk_forensics -i disk.dd -o info

# Generate timeline
./cli.sh disk_forensics -i disk.dd -o timeline

# List all files
./cli.sh disk_forensics -i disk.dd -o list

# Find deleted files
./cli.sh disk_forensics -i disk.dd -o deleted

# Search for strings
./cli.sh disk_forensics -i disk.dd -o search -s "password"

# Compute file hashes
./cli.sh disk_forensics -i disk.dd -o hashes
```

### Common Investigation Workflows

**Full Disk Analysis:**
```bash
# 1. Get filesystem info
./cli.sh disk_forensics -i evidence.dd -o info

# 2. Generate timeline
./cli.sh disk_forensics -i evidence.dd -o timeline

# 3. List all files
./cli.sh disk_forensics -i evidence.dd -o list

# 4. Find deleted files
./cli.sh disk_forensics -i evidence.dd -o deleted
```

**Keyword Search:**
```bash
./cli.sh disk_forensics -i evidence.dd -o search -s "confidential"
./cli.sh disk_forensics -i evidence.dd -o search -s "password"
./cli.sh disk_forensics -i evidence.dd -o search -s "credit card"
```

**Hash Analysis:**
```bash
./cli.sh disk_forensics -i evidence.dd -o hashes
```

### Output Location
Results are saved in `forensics/results/disk_TIMESTAMP/`

## Understanding Results

### Memory Analysis Results

Each analysis creates a directory with:
- `metadata.json` - Analysis information (hash, size, timestamp)
- `<plugin>.txt` - Output from each plugin
- `iocs.json` - Extracted indicators of compromise
- `timeline.csv` - Timeline of events
- `summary.txt` - Analysis summary

Example:
```
forensics/results/memory_20231112_143022_1234/
├── metadata.json
├── pslist.txt          # Running processes
├── netscan.txt         # Network connections
├── malfind.txt         # Suspicious code
├── iocs.json           # Extracted IOCs
├── timeline.csv        # Event timeline
└── summary.txt         # Summary report
```

### Disk Analysis Results

Each analysis creates a directory with:
- `metadata.json` - Analysis information
- `timeline.csv` - Filesystem timeline
- `file_list.txt` - All files in image
- `deleted_files.txt` - Deleted file entries
- `file_hashes.csv` - Hash values
- `search_results.txt` - String search results
- `filesystem_info.txt` - FS metadata
- `summary.txt` - Analysis summary

Example:
```
forensics/results/disk_20231112_143022_5678/
├── metadata.json
├── timeline.csv           # MAC times
├── file_list.txt         # All files
├── deleted_files.txt     # Deleted files
├── file_hashes.csv       # MD5/SHA hashes
├── search_results.txt    # String matches
└── summary.txt           # Summary report
```

## Tips and Tricks

### Speed Up Analysis

1. **Use Caching**: Results are cached for 24 hours
   ```bash
   # First run - slow
   ./cli.sh memory_forensics -d memory.dump -p "pslist"
   
   # Second run - instant (uses cache)
   ./cli.sh memory_forensics -d memory.dump -p "pslist"
   ```

2. **Run Specific Plugins**: Don't run all plugins if you don't need them
   ```bash
   # Fast - only what you need
   ./cli.sh memory_forensics -d memory.dump -p "pslist,netscan"
   
   # Slow - all plugins
   ./cli.sh memory_forensics -d memory.dump -p "pslist,pstree,netscan,malfind,..."
   ```

3. **Clear Old Results**: Free up disk space
   ```bash
   rm -rf forensics/results/*
   rm -rf forensics/cache/*
   ```

### Manage Output

View results:
```bash
# Memory forensics
ls -l forensics/results/memory_*/
cat forensics/results/memory_*/summary.txt
cat forensics/results/memory_*/iocs.json

# Disk forensics
ls -l forensics/results/disk_*/
cat forensics/results/disk_*/summary.txt
head -20 forensics/results/disk_*/timeline.csv
```

Search results:
```bash
# Find processes named "malware"
grep -i "malware" forensics/results/memory_*/pslist.txt

# Find IP addresses
grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' forensics/results/memory_*/netscan.txt | sort -u

# Find suspicious files
grep -i "suspicious" forensics/results/disk_*/file_list.txt
```

### Debug Issues

Enable verbose logging:
```bash
export PARROT_LOG_LEVEL="DEBUG"
export PARROT_DEBUG="true"

./cli.sh memory_forensics -d memory.dump -p pslist

# Check logs
tail -f logs/forensics.log
```

## Common Issues

### Volatility Not Found
```bash
ERROR: Required command 'vol' not found
ERROR: Required Python package 'volatility3' not found

# Fix:
pip3 install volatility3
```

### SleuthKit Not Found
```bash
ERROR: Required command 'fls' not found

# Fix:
sudo apt-get install sleuthkit
```

### Out of Disk Space
```bash
# Clean old results
rm -rf forensics/results/*
rm -rf forensics/cache/*
```

### Permission Denied
```bash
# Fix permissions
chmod -R u+w forensics/
```

## Advanced Usage

### Custom Plugin Workflows

Create a script for repeated analysis:
```bash
#!/bin/bash
# analyze_malware.sh
DUMP="$1"

echo "Running triage plugins..."
./cli.sh memory_forensics -d "$DUMP" -p "pslist,pstree,netscan"

echo "Running malware plugins..."
./cli.sh memory_forensics -d "$DUMP" -p "malfind,apihooks,ldrmodules"

echo "Running file analysis..."
./cli.sh memory_forensics -d "$DUMP" -p "filescan,handles,dlllist"

echo "Analysis complete!"
ls -l forensics/results/
```

### Automated Reporting

Extract key findings:
```bash
#!/bin/bash
# generate_report.sh
RESULT_DIR="forensics/results/memory_$(ls -t forensics/results/ | grep memory | head -1)"

echo "=== Security Investigation Report ===" > report.txt
echo "" >> report.txt
echo "Analysis ID: $(basename $RESULT_DIR)" >> report.txt
echo "Timestamp: $(date)" >> report.txt
echo "" >> report.txt

echo "=== IOCs Extracted ===" >> report.txt
cat "$RESULT_DIR/iocs.json" >> report.txt
echo "" >> report.txt

echo "=== Network Connections ===" >> report.txt
cat "$RESULT_DIR/netscan.txt" | head -20 >> report.txt
echo "" >> report.txt

echo "=== Suspicious Processes ===" >> report.txt
cat "$RESULT_DIR/malfind.txt" | head -20 >> report.txt

echo "Report saved to report.txt"
```

## Getting Help

- Full documentation: `docs/FORENSICS.md`
- Script help: `./cli.sh memory_forensics --help`
- List plugins: `./cli.sh memory_forensics --list-plugins`
- Check dependencies: `./cli.sh memory_forensics --check`

## Next Steps

1. Install required tools (Volatility 3, SleuthKit)
2. Run dependency check
3. Analyze sample evidence
4. Review results in `forensics/results/`
5. Read full documentation in `docs/FORENSICS.md`

For detailed information and best practices, see the complete documentation.
