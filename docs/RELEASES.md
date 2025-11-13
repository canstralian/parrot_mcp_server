# Release Verification Guide

This document describes how to verify the authenticity and integrity of Parrot MCP Server releases.

## Overview

The Parrot MCP Server team signs all official releases with GPG keys to ensure authenticity and integrity. This allows you to verify that a release file you downloaded was indeed provided by the Parrot MCP Server team and has not been tampered with.

## What Gets Signed

All release artifacts are signed, including:

- Source code archives (.tar.gz, .zip)
- Binary distributions (if applicable)
- Installation scripts
- Documentation archives

## Verification Files

Each release includes the following verification files:

### GPG Signatures (.asc files)

All release files are accompanied by detached GPG signatures with the `.asc` suffix. These signatures are uploaded to:

- **GitHub Releases**: Available on the [releases page](https://github.com/canstralian/parrot_mcp_server/releases)
- **Package Registries**: Available alongside packages on any distribution platforms (e.g., package managers)

### Checksums (.sha256 files)

Each release also includes SHA-256 checksums in files with the `.sha256` suffix. These provide an additional layer of verification to ensure file integrity.

## Public Keys

### Key Location

Public GPG keys used for signing releases are stored in the `gpg-keys/` directory at the root of the repository. You can also find them on the [GitHub repository](https://github.com/canstralian/parrot_mcp_server/tree/main/gpg-keys).

### Key Naming Convention

Keys are named using the following format:

- `<first_version>-<last_version>.gpg` - For keys that have been rotated out
- `<first_version>-current.gpg` - For the key currently being used for new releases

**Example:**
- `v1.0.0-v2.5.0.gpg` - Key used for releases from v1.0.0 to v2.5.0
- `v2.6.0-current.gpg` - Currently active key for releases from v2.6.0 onwards

### Key Fingerprints

Always verify key fingerprints before importing. Current key fingerprints are listed in the [SECURITY.md](../SECURITY.md#release-signing-keys) file.

## How to Verify a Release

### Prerequisites

You need GnuPG (GPG) installed on your system:

```bash
# Debian/Ubuntu
sudo apt-get install gnupg

# macOS
brew install gnupg

# Fedora/RHEL
sudo dnf install gnupg
```

### Step 1: Download Release Files

Download the release file and its corresponding signature from the [GitHub releases page](https://github.com/canstralian/parrot_mcp_server/releases):

```bash
# Example for version v1.0.0
wget https://github.com/canstralian/parrot_mcp_server/releases/download/v1.0.0/parrot-mcp-server-v1.0.0.tar.gz
wget https://github.com/canstralian/parrot_mcp_server/releases/download/v1.0.0/parrot-mcp-server-v1.0.0.tar.gz.asc
wget https://github.com/canstralian/parrot_mcp_server/releases/download/v1.0.0/parrot-mcp-server-v1.0.0.tar.gz.sha256
```

### Step 2: Import the Public Key

First, download the appropriate public key for your release version:

```bash
# Clone the repository or download the specific key file
wget https://raw.githubusercontent.com/canstralian/parrot_mcp_server/main/gpg-keys/v1.0.0-current.gpg

# Import the key
gpg --import v1.0.0-current.gpg
```

### Step 3: Verify the Key Fingerprint

**IMPORTANT**: Always verify the key fingerprint matches the one published in our documentation:

```bash
gpg --fingerprint
```

Compare the output with the fingerprints listed in [SECURITY.md](../SECURITY.md#release-signing-keys).

### Step 4: Verify the GPG Signature

Verify the release file using the GPG signature:

```bash
gpg --verify parrot-mcp-server-v1.0.0.tar.gz.asc parrot-mcp-server-v1.0.0.tar.gz
```

You should see output similar to:

```
gpg: Signature made [DATE]
gpg:                using RSA key [KEY_ID]
gpg: Good signature from "Parrot MCP Server Release Team <releases@parrot-mcp.example>"
```

**Warning**: If you see `BAD signature`, do not use the file. It may have been tampered with.

### Step 5: Verify the Checksum

Additionally, verify the SHA-256 checksum:

```bash
# Verify the checksum
sha256sum -c parrot-mcp-server-v1.0.0.tar.gz.sha256
```

You should see:

```
parrot-mcp-server-v1.0.0.tar.gz: OK
```

## Automated Verification Script

For convenience, we provide a verification script:

```bash
#!/bin/bash
# verify-release.sh - Automated release verification script

set -euo pipefail

RELEASE_FILE="$1"
VERSION="$2"

if [ -z "$RELEASE_FILE" ] || [ -z "$VERSION" ]; then
    echo "Usage: $0 <release-file> <version>"
    echo "Example: $0 parrot-mcp-server-v1.0.0.tar.gz v1.0.0"
    exit 1
fi

echo "==> Downloading signature and checksum files..."
wget -q "https://github.com/canstralian/parrot_mcp_server/releases/download/${VERSION}/${RELEASE_FILE}.asc"
wget -q "https://github.com/canstralian/parrot_mcp_server/releases/download/${VERSION}/${RELEASE_FILE}.sha256"

echo "==> Downloading and importing GPG key..."
KEY_FILE=$(curl -s "https://api.github.com/repos/canstralian/parrot_mcp_server/contents/gpg-keys" | \
    grep -o '"name": "[^"]*current.gpg"' | cut -d'"' -f4 | head -1)
wget -q "https://raw.githubusercontent.com/canstralian/parrot_mcp_server/main/gpg-keys/${KEY_FILE}"
gpg --import "${KEY_FILE}" 2>/dev/null || true

echo "==> Verifying GPG signature..."
if gpg --verify "${RELEASE_FILE}.asc" "${RELEASE_FILE}" 2>&1 | grep -q "Good signature"; then
    echo "✓ GPG signature verification passed"
else
    echo "✗ GPG signature verification FAILED"
    exit 1
fi

echo "==> Verifying SHA-256 checksum..."
if sha256sum -c "${RELEASE_FILE}.sha256" 2>&1 | grep -q "OK"; then
    echo "✓ Checksum verification passed"
else
    echo "✗ Checksum verification FAILED"
    exit 1
fi

echo ""
echo "==> ✓ All verifications passed successfully!"
echo "The release file '${RELEASE_FILE}' is authentic and has not been tampered with."
```

Save this script and run it:

```bash
chmod +x verify-release.sh
./verify-release.sh parrot-mcp-server-v1.0.0.tar.gz v1.0.0
```

## Troubleshooting

### "No public key" Error

If you see an error like:

```
gpg: Can't check signature: No public key
```

Make sure you've imported the correct public key (Step 2 above).

### "This key is not certified with a trusted signature"

This warning is normal if you haven't explicitly trusted the key. You can verify the fingerprint (Step 3) and then trust the key:

```bash
gpg --edit-key <KEY_ID>
# At the gpg> prompt, type: trust
# Select trust level 5 (ultimate) or 4 (full)
# Type: quit
```

### Checksum Mismatch

If the checksum doesn't match:

1. Re-download the file - it may have been corrupted during download
2. Ensure you're comparing the correct file with the correct checksum file
3. If the problem persists, report it immediately to security@parrot-mcp.example or via our [security policy](../SECURITY.md)

## Security Considerations

### Best Practices

1. **Always verify both GPG signature and checksum** - This provides defense in depth
2. **Verify the key fingerprint** - Don't skip Step 3; it's critical for security
3. **Use the latest release** - Older releases may contain known vulnerabilities
4. **Download from official sources only** - Only use GitHub releases or official mirrors
5. **Keep GPG up to date** - Ensure your GPG installation is current

### What This Protects Against

Release verification protects against:

- **Man-in-the-middle attacks**: Ensures files haven't been intercepted and modified
- **Compromised mirrors**: Verifies authenticity even from third-party sources
- **Corrupted downloads**: Checksums detect transmission errors
- **Supply chain attacks**: Confirms releases come from the official team

### What This Doesn't Protect Against

Release verification does NOT protect against:

- **Compromised signing keys**: If our private keys are stolen, verification will still pass
- **Vulnerabilities in the code**: Verification only confirms authenticity, not security
- **Zero-day exploits**: Verification doesn't detect unknown vulnerabilities

Always follow our [security policy](../SECURITY.md) and keep the software updated.

## Reporting Security Issues

If you discover a problem with release signatures or suspect a compromised release, please report it immediately:

- **Email**: security@parrot-mcp.example
- **GitHub Security Advisory**: Use the "Report a vulnerability" feature
- **See**: [SECURITY.md](../SECURITY.md) for full details

## Additional Resources

- [GnuPG Documentation](https://www.gnupg.org/documentation/)
- [GitHub: About commit signature verification](https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification)
- [Parrot MCP Server Security Policy](../SECURITY.md)
- [Parrot MCP Server Changelog](../rpi-scripts/CHANGELOG.md)

---

**Last Updated**: 2025-11-13
**Applies to**: All releases v1.0.0 and later
