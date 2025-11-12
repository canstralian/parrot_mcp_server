# Parrot MCP Server

![Build Status](https://img.shields.io/badge/build-passing-brightgreen)
![Test Status](https://img.shields.io/badge/tests-passing-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

## Features

- **Scalability**: The server can handle numerous connections concurrently.
- **Flexible Configuration**: Easily adjustable settings to meet different deployment needs.
- **Robust Security**: Built with industry-standard security practices.
- **SARIF Security Analysis**: Comprehensive static analysis with SARIF 2.1.0 compliant output for shell scripts.
  - Stable rule identifiers with semantic versioning
  - Deterministic, reproducible scan results
  - Complete provenance metadata for audit trails
  - Integration-ready for GitHub Code Scanning and CI/CD pipelines

## Philosophy

At Parrot MCP Server, we believe in empowering developers with tools that prioritize performance and ease of use. Our philosophy is centered around creating a community-driven project that evolves based on user feedback and technological advancements.

## Community Collaboration

We encourage contributions from developers around the world. Join our community to report issues, propose enhancements, or submit pull requests. Together, we can make the Parrot MCP Server even better!

## Quick Start

### SARIF Security Scanning

Scan your shell scripts for security vulnerabilities:

```bash
cd rpi-scripts
./cli.sh sarif scan ./scripts output.sarif
./cli.sh sarif validate output.sarif
```

For detailed documentation, see:
- [SARIF ABI Contract Documentation](rpi-scripts/docs/SARIF_ABI_CONTRACT.md)
- [Usage Examples](rpi-scripts/docs/SARIF_USAGE_EXAMPLES.md)

### Running the MCP Server

```bash
cd rpi-scripts
./start_mcp_server.sh
```

## Future Goals

In the upcoming releases, we aim to:

- Introduce multi-language support.
- Improve integration with popular CI/CD tools.
- Expand our community outreach and events.
- Extend SARIF scanning to additional languages.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.