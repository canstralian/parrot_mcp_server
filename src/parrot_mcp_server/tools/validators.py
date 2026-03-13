"""Shared input validation for all pentest tools.

Every tool argument passes through these validators before reaching
subprocess or filesystem calls. No raw user strings in shell contexts.
"""
from __future__ import annotations

import os
import re
from pathlib import Path

# ---------------------------------------------------------------------------
# Compiled regex patterns
# ---------------------------------------------------------------------------

_IP_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}"
    r"(?:25[0-5]|2[0-4]\d|[01]?\d\d?)$"
)

# Simplified hostname per RFC 1123 (labels up to 63 chars, dots between)
_HOSTNAME_RE = re.compile(
    r"^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)"
    r"(?:\.(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?))*$"
)

# CIDR notation (IPv4 only)
_CIDR_RE = re.compile(
    r"^(?:(?:25[0-5]|2[0-4]\d|[01]?\d\d?)\.){3}"
    r"(?:25[0-5]|2[0-4]\d|[01]?\d\d?)/(?:[12]?\d|3[0-2])$"
)

# Port specification: single, range, or comma-separated combos (e.g. 80,443,8080-8090)
_PORT_SPEC_RE = re.compile(r"^(?:\d{1,5}(?:-\d{1,5})?(?:,\d{1,5}(?:-\d{1,5})?)*)$")

# Safe URL path (no shell metacharacters)
_URL_PATH_RE = re.compile(r"^[a-zA-Z0-9._/\-?=&%+#@~:;,\[\]]*$")

# Extension list: letters/numbers, comma-separated
_EXT_RE = re.compile(r"^[a-zA-Z0-9](?:[a-zA-Z0-9,]*[a-zA-Z0-9])?$")

# ---------------------------------------------------------------------------
# Loot directory
# ---------------------------------------------------------------------------

_loot_env = os.environ.get("PARROT_LOOT_DIR", "")
LOOT_DIR: Path = Path(_loot_env) if _loot_env else Path.cwd() / "loot"


def ensure_loot_dir() -> Path:
    """Create the loot directory (mode 700) and return its Path."""
    LOOT_DIR.mkdir(parents=True, exist_ok=True)
    LOOT_DIR.chmod(0o700)
    return LOOT_DIR


# ---------------------------------------------------------------------------
# Target / network validators
# ---------------------------------------------------------------------------


def validate_target(target: str) -> str:
    """Return a cleaned IP, CIDR, or hostname; raise ValueError otherwise."""
    t = target.strip()
    if _IP_RE.match(t) or _CIDR_RE.match(t) or _HOSTNAME_RE.match(t):
        return t
    raise ValueError(
        f"Invalid target '{target}': must be an IPv4 address, CIDR block, or hostname."
    )


def validate_ports(ports: str) -> str:
    """Validate nmap-style port specification; raise ValueError on bad input."""
    p = ports.strip()
    if p in ("top100", "top1000", "-"):
        return p
    if _PORT_SPEC_RE.match(p):
        # Ensure each port number is in valid range
        for part in p.replace("-", ",").split(","):
            if part and not (1 <= int(part) <= 65535):
                raise ValueError(f"Port {part} out of range 1-65535.")
        return p
    raise ValueError(
        f"Invalid port specification '{ports}'. "
        "Use 'top100', 'top1000', a number, range, or comma-separated list."
    )


def validate_port_number(port: int) -> int:
    """Validate a single port integer."""
    if not (1 <= port <= 65535):
        raise ValueError(f"Port {port} out of range 1-65535.")
    return port


# ---------------------------------------------------------------------------
# HTTP validators
# ---------------------------------------------------------------------------


def validate_http_method(method: str) -> str:
    """Restrict to a safe set of HTTP methods."""
    m = method.strip().upper()
    if m not in {"GET", "HEAD", "POST", "OPTIONS", "PUT", "DELETE", "PATCH"}:
        raise ValueError(f"Unsupported HTTP method '{method}'.")
    return m


def validate_url_path(path: str) -> str:
    """Validate a URL path (no shell metacharacters)."""
    p = path.strip()
    if not p.startswith("/"):
        raise ValueError("URL path must start with '/'.")
    if not _URL_PATH_RE.match(p):
        raise ValueError(f"Invalid characters in URL path '{path}'.")
    return p


# ---------------------------------------------------------------------------
# Filesystem path validators
# ---------------------------------------------------------------------------


def validate_loot_filename(filename: str) -> Path:
    """
    Validate a loot filename and return the resolved Path, strictly confined
    to LOOT_DIR to prevent path traversal.
    """
    # Strip any directory component — only accept bare filenames
    name = Path(filename).name
    resolved = (LOOT_DIR / name).resolve()
    if not str(resolved).startswith(str(LOOT_DIR.resolve())):
        raise ValueError(f"Path traversal detected in loot filename: '{filename}'.")
    return resolved


def validate_scan_base_path(path: str) -> Path:
    """
    Validate a local filesystem base path for post-exploitation analysis.
    Rejects shell metacharacters; does NOT restrict to a specific base.
    """
    p = path.strip()
    # Reject shell metacharacters
    bad_chars = set(";|&`$><!()")
    if any(c in p for c in bad_chars):
        raise ValueError(f"Shell metacharacters detected in path: '{path}'.")
    resolved = Path(p).resolve()
    return resolved


def validate_wordlist_path(wordlist: str) -> Path:
    """Validate that a wordlist is an absolute path pointing to an existing file."""
    wl = Path(wordlist)
    if not wl.is_absolute():
        raise ValueError("Wordlist must be an absolute path.")
    if not wl.exists():
        raise ValueError(f"Wordlist file not found: '{wordlist}'.")
    if not wl.is_file():
        raise ValueError(f"Wordlist path is not a file: '{wordlist}'.")
    return wl


def validate_extensions(extensions: str) -> str:
    """Validate a comma-separated extension list (e.g. 'php,html,txt')."""
    ext = extensions.strip().lower()
    if not _EXT_RE.match(ext):
        raise ValueError(
            f"Invalid extension list '{extensions}'. "
            "Use comma-separated alphanumeric extensions (e.g. 'php,html,txt')."
        )
    return ext
