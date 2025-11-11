
# Raspberry Pi 5 Bash Script Library

This project is a robust, production-ready library of Bash scripts for Raspberry Pi 5, managed by a central CLI tool (`cli.sh`).
It includes system maintenance, automation, and developer-friendly features for reliability and ease of use.

## Usage

```sh
./cli.sh <script> [args]
```

- Lists available scripts if no argument is given.
- Runs the specified script from the `scripts/` directory.
- Run `./cli.sh` with no arguments for an interactive menu.

## Adding Scripts

1. Place your Bash script in the `scripts/` directory.
2. Name it `<name>.sh` and make it executable (`chmod +x scripts/<name>.sh`).
3. It will be automatically available via `cli.sh <name>` or from the menu.

## Example

```sh
./cli.sh hello
```

## SARIF Security Analysis

The library now includes a comprehensive SARIF (Static Analysis Results Interchange Format) ABI Contract implementation for security scanning of shell scripts.

### Quick Start

```sh
# Scan a directory for security issues
./cli.sh sarif scan ./scripts output.sarif

# Scan a single file
./cli.sh sarif file myScript.sh findings.sarif

# Validate SARIF output
./cli.sh sarif validate output.sarif

# List available security rules
./cli.sh sarif rules list
```

### Features

- **Rule Identifier Stability**: Stable rule IDs with semantic versioning
- **Deterministic Output**: Reproducible results across runs
- **Provenance Metadata**: Complete chain of custody for audit trails
- **Comprehensive Validation**: SARIF 2.1.0 schema compliance checking
- **Golden Output Tests**: Regression testing for deterministic behavior

For detailed documentation, see:
- [SARIF ABI Contract Documentation](docs/SARIF_ABI_CONTRACT.md)
- [Usage Examples](docs/SARIF_USAGE_EXAMPLES.md)

## Automated Maintenance Scheduling

To automate all recommended maintenance tasks, run:

```sh
./cli.sh setup_cron
```

This will install cron jobs for updates, cache cleaning, disk checks, backups, and log rotation. View your crontab with `crontab -l`.

You can still manually edit or add cron jobs as needed.

## Setup

- Ensure `cli.sh` is executable: `chmod +x cli.sh`
- Optionally run `make install` or `./install.sh` if provided.

## Code Quality & Automation

- All scripts are linted with [ShellCheck](https://www.shellcheck.net/) and formatted with [shfmt](https://github.com/mvdan/sh).
- To lint scripts manually:

 ```sh
 shellcheck cli.sh scripts/*.sh
 ```

- To format scripts:

 ```sh
 shfmt -w cli.sh scripts/*.sh
 ```

- Continuous Integration (CI) runs ShellCheck, shfmt, and basic script tests on every push and pull request (see `.github/workflows/ci.yml`).
- See `TESTING.md` for more details on manual and automated testing.

## Contributing & Community

- See `CONTRIBUTING.md` for guidelines.
- All contributors must follow the `CODE_OF_CONDUCT.md`.
- Use the provided issue and pull request templates for contributions.

## License

MIT
