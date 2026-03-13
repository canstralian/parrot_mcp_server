#!/usr/bin/env python3
"""
Pre-tool-use enforcement bus for Parrot MCP Server.

Runs before every tool call and validates against five security checks:
  1. IPC directory safety  — rejects /tmp paths in production
  2. Engagement auth gate  — MCP tools require PARROT_ENGAGEMENT_ACTIVE
  3. Blocked command patterns — deny-list of destructive shell patterns
  4. Injection-character detection — flags shell metacharacters in arguments
  5. MCP argument sanitization — validates MCP tool argument shapes

Exit codes:
  0  — allow the tool call to proceed
  2  — hard-block the tool call (Claude will not execute it)
"""

import json
import os
import re
import sys

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Patterns that must never appear in Bash tool commands
BLOCKED_CMD_PATTERNS: list[re.Pattern] = [
    re.compile(r"\brm\s+-rf\b"),
    re.compile(r"\beval\b"),
    re.compile(r"\bexec\b"),
    re.compile(r"\bcurl\b"),
    re.compile(r"\bwget\b"),
    re.compile(r"\bsudo\b"),
    re.compile(r"\bdd\s+if="),
    re.compile(r"\bmkfs\b"),
    re.compile(r"\bfdisk\b"),
    re.compile(r"\bnc\b|\bnetcat\b"),
    re.compile(r"\bnmap\b"),
    re.compile(r"\bkill\s+-9\b"),
    re.compile(r"\bpkill\b"),
    re.compile(r"\bshutdown\b"),
    re.compile(r"\breboot\b"),
    re.compile(r"\bcrontab\s+-r\b"),
    re.compile(r">\s*/dev/(sd|nvme|mmcblk)"),   # raw device writes
    re.compile(r"\bchmod\s+777\b"),
    re.compile(r"\bchown\s+root\b"),
]

# Shell injection metacharacters that should not appear inside MCP arguments
INJECTION_CHARS_RE = re.compile(r"[;&|`$<>\\]")

# MCP tool names served by Parrot servers (prefix match)
PARROT_MCP_PREFIXES = ("mcp__parrot-bash__", "mcp__parrot-python__", "mcp__parrot-workflow__")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _is_production() -> bool:
    return os.environ.get("PARROT_ENV", "dev").lower() == "production"


def _engagement_active() -> bool:
    return os.environ.get("PARROT_ENGAGEMENT_ACTIVE", "").strip().lower() in ("1", "true", "yes")


def _block(reason: str) -> None:
    payload = {"decision": "block", "reason": reason}
    print(json.dumps(payload))
    sys.exit(2)


def _allow() -> None:
    sys.exit(0)


# ---------------------------------------------------------------------------
# Check 1 — IPC directory safety
# ---------------------------------------------------------------------------


def check_ipc_safety(tool_name: str, tool_input: dict) -> None:
    if not _is_production():
        return
    raw = json.dumps(tool_input)
    if "/tmp" in raw:
        _block(
            f"[IPC-SAFETY] Tool '{tool_name}' references /tmp which is disallowed "
            "in production. Use PARROT_IPC_DIR instead."
        )


# ---------------------------------------------------------------------------
# Check 2 — Engagement auth gate
# ---------------------------------------------------------------------------


def check_engagement_gate(tool_name: str) -> None:
    is_parrot_mcp = any(tool_name.startswith(p) for p in PARROT_MCP_PREFIXES)
    if is_parrot_mcp and not _engagement_active():
        _block(
            f"[ENGAGEMENT-GATE] Tool '{tool_name}' requires an active engagement. "
            "Set PARROT_ENGAGEMENT_ACTIVE=1 to authorize."
        )


# ---------------------------------------------------------------------------
# Check 3 — Blocked command patterns
# ---------------------------------------------------------------------------


def check_blocked_commands(tool_name: str, tool_input: dict) -> None:
    if tool_name != "Bash":
        return
    command: str = tool_input.get("command", "")
    for pattern in BLOCKED_CMD_PATTERNS:
        if pattern.search(command):
            _block(
                f"[BLOCKED-CMD] Command matches denied pattern '{pattern.pattern}'. "
                f"Tool: {tool_name}"
            )


# ---------------------------------------------------------------------------
# Check 4 — Injection character detection
# ---------------------------------------------------------------------------


def check_injection_chars(tool_name: str, tool_input: dict) -> None:
    # Only inspect MCP tool arguments (not Bash, which legitimately uses these)
    if not any(tool_name.startswith(p) for p in PARROT_MCP_PREFIXES):
        return
    for key, value in tool_input.items():
        if isinstance(value, str) and INJECTION_CHARS_RE.search(value):
            _block(
                f"[INJECTION] MCP argument '{key}' for tool '{tool_name}' contains "
                f"shell metacharacters: {repr(value[:120])}"
            )


# ---------------------------------------------------------------------------
# Check 5 — MCP argument sanitization
# ---------------------------------------------------------------------------


def check_mcp_argument_shapes(tool_name: str, tool_input: dict) -> None:
    if not any(tool_name.startswith(p) for p in PARROT_MCP_PREFIXES):
        return
    for key, value in tool_input.items():
        # Reject non-primitive nested structures beyond one level deep
        if isinstance(value, (list, dict)):
            try:
                serialized = json.dumps(value)
            except (TypeError, ValueError) as exc:
                _block(
                    f"[MCP-ARG] Tool '{tool_name}' argument '{key}' is not "
                    f"JSON-serializable: {exc}"
                )
            if len(serialized) > 4096:
                _block(
                    f"[MCP-ARG] Tool '{tool_name}' argument '{key}' exceeds 4096-byte "
                    "limit for structured values."
                )


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    raw = sys.stdin.read().strip()
    if not raw:
        _allow()

    try:
        event = json.loads(raw)
    except json.JSONDecodeError:
        # Malformed input — fail open (log but allow) to avoid blocking Claude on
        # legitimate calls when the hook pipe is noisy.
        _allow()

    tool_name: str = event.get("tool_name", "")
    tool_input: dict = event.get("tool_input", {})

    check_ipc_safety(tool_name, tool_input)
    check_engagement_gate(tool_name)
    check_blocked_commands(tool_name, tool_input)
    check_injection_chars(tool_name, tool_input)
    check_mcp_argument_shapes(tool_name, tool_input)

    _allow()


if __name__ == "__main__":
    main()
