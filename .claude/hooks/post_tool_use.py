#!/usr/bin/env python3
"""
Post-tool-use audit and sanitization layer for Parrot MCP Server.

After every tool completes this hook:
  1. Appends a chained SHA-256 audit entry to the session log (JSONL)
  2. Scans tool output for leaked secrets via regex patterns
  3. Performs heuristic scope-drift detection on IP addresses in output

The hook always exits 0 — it is an audit layer, not a blocking gate.
Hard blocking based on accumulated audit evidence happens in stop_gate.py.
"""

import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LOG_DIR = Path(os.environ.get("PARROT_LOG_DIR", "/var/log/parrot"))
SESSION_ID = os.environ.get("PARROT_SESSION_ID", "unknown")
AUDIT_LOG = LOG_DIR / f"audit_{SESSION_ID}.jsonl"

# Secret leak detection patterns
SECRET_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("api_key_generic",    re.compile(r"(?i)(api[_-]?key|apikey)\s*[:=]\s*['\"]?([A-Za-z0-9_\-]{20,})")),
    ("aws_access_key",     re.compile(r"AKIA[0-9A-Z]{16}")),
    ("aws_secret_key",     re.compile(r"(?i)aws[_-]?secret[_-]?access[_-]?key\s*[:=]\s*['\"]?([A-Za-z0-9/+=]{40})")),
    ("pem_key_block",      re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("github_token",       re.compile(r"gh[pousr]_[A-Za-z0-9]{36,}")),
    ("slack_token",        re.compile(r"xox[baprs]-[0-9A-Za-z\-]{10,}")),
    ("heroku_api_key",     re.compile(r"(?i)heroku[_-]?api[_-]?key\s*[:=]\s*['\"]?([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})")),
    ("jwt_token",          re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}")),
    ("generic_password",   re.compile(r"(?i)(password|passwd|pwd)\s*[:=]\s*['\"]([^'\"]{8,})['\"]")),
]

# RFC-1918 private ranges for scope-drift heuristic
PRIVATE_IP_RE = re.compile(
    r"\b(?:"
    r"10\.\d{1,3}\.\d{1,3}\.\d{1,3}"
    r"|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}"
    r"|192\.168\.\d{1,3}\.\d{1,3}"
    r")\b"
)

# Public routable IPv4 (not loopback/link-local/private)
PUBLIC_IP_RE = re.compile(
    r"\b(?!10\.|172\.(?:1[6-9]|2\d|3[01])\.|192\.168\.|127\.|169\.254\.)"
    r"(?:[1-9]\d{0,2}\.){3}[1-9]\d{0,2}\b"
)

# ---------------------------------------------------------------------------
# Audit log
# ---------------------------------------------------------------------------


def _prev_hash() -> str:
    """
    Get the SHA-256 hash of the last non-empty line in the audit log.
    
    Returns:
        A 64-character hex SHA-256 digest of the last non-empty audit log line. If the audit log does not exist, is empty, or cannot be read, returns a string of 64 zeros.
    """
    if not AUDIT_LOG.exists():
        return "0" * 64
    try:
        with AUDIT_LOG.open("rb") as fh:
            # Scan to last non-empty line efficiently
            fh.seek(0, 2)
            size = fh.tell()
            if size == 0:
                return "0" * 64
            pos = max(0, size - 4096)
            fh.seek(pos)
            lines = fh.read().split(b"\n")
            for line in reversed(lines):
                line = line.strip()
                if line:
                    return hashlib.sha256(line).hexdigest()
    except OSError:
        pass
    return "0" * 64


def _write_audit_entry(entry: dict) -> None:
    """
    Append a chained audit entry to the session audit JSONL log.
    
    Injects a "prev_hash" (SHA-256 of the last non-empty audit line or zero-hash) into the provided entry, computes
    and injects the entry's own "hash" (SHA-256 of the serialized entry), and appends the final JSON line to the
    configured audit log file, creating the log directory if necessary.
    
    Parameters:
        entry (dict): Mutable mapping representing the audit entry; this function will add "prev_hash" and "hash"
            keys and persist the resulting object.
    
    Notes:
        If the audit log cannot be written due to an OSError, a warning is printed to stderr and the function returns
        without raising an exception.
    """
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        prev = _prev_hash()
        entry["prev_hash"] = prev
        serialized = json.dumps(entry, separators=(",", ":"), sort_keys=True)
        entry["hash"] = hashlib.sha256(serialized.encode()).hexdigest()
        final = json.dumps(entry, separators=(",", ":"), sort_keys=True)
        with AUDIT_LOG.open("a") as fh:
            fh.write(final + "\n")
    except OSError:
        # Audit log unavailable — write a warning to stderr and continue
        print("[AUDIT] WARNING: could not write audit log entry", file=sys.stderr)


# ---------------------------------------------------------------------------
# Secret detection
# ---------------------------------------------------------------------------


def _scan_secrets(output: str) -> list[str]:
    """
    Detects which configured secret patterns appear in the provided output.
    
    Parameters:
        output (str): Text to scan for secret patterns.
    
    Returns:
        matched_patterns (list[str]): Names of secret patterns that matched the output; empty list if none.
    """
    hits: list[str] = []
    for name, pattern in SECRET_PATTERNS:
        if pattern.search(output):
            hits.append(name)
    return hits


# ---------------------------------------------------------------------------
# Scope drift heuristic
# ---------------------------------------------------------------------------


def _scan_scope_drift(output: str) -> dict:
    """
    Detect IP-based scope drift in the provided output string and report seen IPs and any that fall outside configured scope.
    
    Reads the PARROT_SCOPE_TARGETS environment variable (comma-separated IPs) to form an allowed target set. Extracts private and public IPv4 addresses from the output and, if scope targets are configured, identifies addresses not present in that target set.
    
    Returns:
        dict: {
            "private_ips_seen": list of unique private IPv4 addresses found in the output,
            "public_ips_seen": list of unique public IPv4 addresses found in the output,
            "out_of_scope_ips": list of IP addresses that were found but are not included in PARROT_SCOPE_TARGETS (empty if no targets configured)
        }
    """
    scope_targets: list[str] = []
    raw = os.environ.get("PARROT_SCOPE_TARGETS", "")
    if raw:
        scope_targets = [s.strip() for s in raw.split(",") if s.strip()]

    private_ips = PRIVATE_IP_RE.findall(output)
    public_ips = PUBLIC_IP_RE.findall(output)

    out_of_scope: list[str] = []
    if scope_targets:
        all_ips = list(set(private_ips + public_ips))
        for ip in all_ips:
            if ip not in scope_targets:
                out_of_scope.append(ip)

    return {
        "private_ips_seen": list(set(private_ips)),
        "public_ips_seen": list(set(public_ips)),
        "out_of_scope_ips": out_of_scope,
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    """
    Process a tool event read from standard input, scan the tool output for secret leaks and scope drift, append a chained audit entry to the session audit log, emit warnings to stderr if issues are found, and exit with status code 0.
    
    Reads JSON from stdin into an event (invalid or missing JSON is treated as an empty event), extracts tool_name, tool_input, and tool_response, normalizes the response to a string, runs secret and scope-drift scans, constructs an audit entry containing timestamp, session id, tool metadata, output metrics, and scan results, and writes the entry to the audit log. If secret patterns or out-of-scope IPs are detected, prints a warning to stderr. Always terminates the process with exit code 0.
    """
    raw = sys.stdin.read().strip()
    event: dict = {}
    if raw:
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            pass

    tool_name: str = event.get("tool_name", "unknown")
    tool_input: dict = event.get("tool_input", {})
    tool_response = event.get("tool_response", {})

    # Flatten output to a string for scanning
    if isinstance(tool_response, dict):
        output_str = json.dumps(tool_response)
    elif isinstance(tool_response, str):
        output_str = tool_response
    else:
        output_str = str(tool_response)

    # --- Secret scan ---
    secret_hits = _scan_secrets(output_str)

    # --- Scope drift scan ---
    scope_info = _scan_scope_drift(output_str)

    # --- Build audit entry ---
    entry: dict = {
        "ts": time.time(),
        "session_id": SESSION_ID,
        "tool_name": tool_name,
        "tool_input_keys": sorted(tool_input.keys()) if isinstance(tool_input, dict) else [],
        "output_len": len(output_str),
        "secret_leak_detected": bool(secret_hits),
        "secret_patterns_matched": secret_hits,
        "scope_drift": scope_info,
        "out_of_scope_detected": bool(scope_info["out_of_scope_ips"]),
    }

    _write_audit_entry(entry)

    # Surface warnings to stderr (visible in Claude Code output)
    if secret_hits:
        print(
            f"[AUDIT] SECRET LEAK DETECTED in output of '{tool_name}': "
            f"{', '.join(secret_hits)}",
            file=sys.stderr,
        )

    if scope_info["out_of_scope_ips"]:
        print(
            f"[AUDIT] SCOPE DRIFT: out-of-scope IPs seen in '{tool_name}' output: "
            f"{scope_info['out_of_scope_ips']}",
            file=sys.stderr,
        )

    sys.exit(0)


if __name__ == "__main__":
    main()
