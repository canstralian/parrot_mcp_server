# GPG Keys for Release Signing

This directory contains the public GPG keys used to sign official releases of the Parrot MCP Server.

## Directory Structure

Keys are named according to the version range they cover:

```
gpg-keys/
├── README.md                    # This file
├── v1.0.0-current.gpg          # Current active key (example)
└── v0.1.0-v0.9.9.gpg           # Previous key (if rotated)
```

## Key Naming Convention

- `<first_version>-<last_version>.gpg` - Keys that have been rotated out
- `<first_version>-current.gpg` - The currently active key for new releases

## For Users: Verifying Releases

To verify a release:

1. **Import the appropriate public key**:
   ```bash
   gpg --import gpg-keys/v1.0.0-current.gpg
   ```

2. **Verify the signature**:
   ```bash
   gpg --verify parrot-mcp-server-v1.0.0.tar.gz.asc parrot-mcp-server-v1.0.0.tar.gz
   ```

For detailed instructions, see the [Release Verification Guide](../docs/RELEASES.md).

## For Maintainers: Managing Release Keys

### Generating a New Release Key

When creating the first release or rotating keys:

```bash
# Generate a new GPG key pair
gpg --full-generate-key

# Choose:
# - Type: RSA and RSA
# - Key size: 4096 bits
# - Expiration: 2 years (recommended)
# - Real name: Parrot MCP Server Release Team
# - Email: releases@parrot-mcp.example (or appropriate contact)

# Export the public key
gpg --armor --export releases@parrot-mcp.example > gpg-keys/v1.0.0-current.gpg

# Get the fingerprint
gpg --fingerprint releases@parrot-mcp.example
```

### Key Information to Document

After generating a key, update the following:

1. **SECURITY.md**: Add the key fingerprint under "Release Signing Keys"
2. **This README**: Add key details to the table below
3. **CHANGELOG**: Note the key change in release notes

### Key Rotation Policy

Keys should be rotated:
- **Every 2 years** - Regular rotation schedule
- **Immediately** if compromised or suspected compromise
- **Before major version changes** (optional but recommended)

When rotating:

1. Generate new key as shown above
2. Rename old key from `*-current.gpg` to `v<first>-v<last>.gpg`
3. Update SECURITY.md with new fingerprint
4. Announce the rotation in release notes
5. Sign the new key with the old key (web of trust)

### Signing a Release

To sign release artifacts:

```bash
#!/bin/bash
# Example release signing script

RELEASE_VERSION="v1.0.0"
RELEASE_FILE="parrot-mcp-server-${RELEASE_VERSION}.tar.gz"

# Create the release archive
git archive --format=tar.gz --prefix=parrot-mcp-server-${RELEASE_VERSION}/ \
    -o "${RELEASE_FILE}" "${RELEASE_VERSION}"

# Generate SHA-256 checksum
sha256sum "${RELEASE_FILE}" > "${RELEASE_FILE}.sha256"

# Sign the release file
gpg --armor --detach-sign --local-user releases@parrot-mcp.example "${RELEASE_FILE}"

# Sign the checksum file
gpg --armor --detach-sign --local-user releases@parrot-mcp.example "${RELEASE_FILE}.sha256"

# Verify signatures
gpg --verify "${RELEASE_FILE}.asc" "${RELEASE_FILE}"
gpg --verify "${RELEASE_FILE}.sha256.asc" "${RELEASE_FILE}.sha256"

echo "Release artifacts created:"
ls -lh "${RELEASE_FILE}"*
```

### Key Security Best Practices

1. **Private Key Storage**:
   - Store private keys on encrypted storage
   - Use hardware security keys (YubiKey) if possible
   - Never commit private keys to version control
   - Use strong passphrase protection

2. **Key Backup**:
   - Keep encrypted backups of private keys
   - Store backups in multiple secure locations
   - Document recovery procedures

3. **Access Control**:
   - Limit who has access to release signing keys
   - Require multiple maintainers to approve releases
   - Use separate keys for different purposes (commits vs releases)

4. **Revocation**:
   - Generate and publish revocation certificate
   - Store revocation certificate securely
   - Know how to revoke if key is compromised

## Current Keys

| Key File | Fingerprint | Valid From | Valid Until | Status | Notes |
|----------|-------------|------------|-------------|--------|-------|
| *To be added* | *TBD* | *TBD* | *TBD* | Pending | First release key to be generated |

## Key Fingerprint Verification

Always verify key fingerprints through multiple channels:

1. **GitHub Repository**: This file and SECURITY.md
2. **Release Announcements**: Project blog/announcements
3. **Social Media**: Official project accounts
4. **Keyservers**: Published to public keyservers (optional)

If fingerprints don't match across channels, **do not trust the key** and report it immediately.

## Reporting Key Issues

If you suspect a key has been compromised or notice fingerprint mismatches:

1. **Do not use** releases signed with the suspect key
2. **Report immediately** via our [Security Policy](../SECURITY.md)
3. **Wait for official response** before using any releases

## Key Distribution

Public keys in this directory are distributed through:

- **GitHub Repository**: This `gpg-keys/` directory
- **GitHub Releases**: Attached to each release
- **Documentation**: Referenced in SECURITY.md and RELEASES.md
- **Keyservers** (optional): `keys.openpgp.org`, `keyserver.ubuntu.com`

## Additional Resources

- [GPG Best Practices](https://riseup.net/en/security/message-security/openpgp/best-practices)
- [Debian Wiki: Creating GPG Keys](https://wiki.debian.org/Creating%20signed%20GitHub%20Releases)
- [Release Verification Guide](../docs/RELEASES.md)
- [Security Policy](../SECURITY.md)

---

**Last Updated**: 2025-11-13
