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
    """
    Determine whether the current runtime environment is production.
    
    Returns:
        True if the PARROT_ENV environment variable equals "production" (case-insensitive), False otherwise.
    """
    return os.environ.get("PARROT_ENV", "dev").lower() == "production"


def _engagement_active() -> bool:
    """
    Checks whether the Parrot engagement feature is enabled via environment.
    
    Determines if the PARROT_ENGAGEMENT_ACTIVE environment variable, after trimming whitespace
    and lowercasing, is set to one of the truthy values "1", "true", or "yes".
    
    Returns:
        `true` if PARROT_ENGAGEMENT_ACTIVE is set to "1", "true", or "yes" (case-insensitive, whitespace ignored), `false` otherwise.
    """
    return os.environ.get("PARROT_ENGAGEMENT_ACTIVE", "").strip().lower() in ("1", "true", "yes")


def _block(reason: str) -> None:
    """
    Emit a JSON payload indicating a blocking decision and terminate the process with exit code 2.
    
    Writes {"decision": "block", "reason": <reason>} to stdout and then exits the interpreter with status 2.
    
    Parameters:
        reason (str): Human-readable explanation included in the emitted JSON payload to indicate why the call was blocked.
    """
    payload = {"decision": "block", "reason": reason}
    print(json.dumps(payload))
    sys.exit(2)


def _allow() -> None:
    """
    Signal that the tool call is allowed and terminate the process with exit code 0.
    """
    sys.exit(0)


# ---------------------------------------------------------------------------
# Check 1 — IPC directory safety
# ---------------------------------------------------------------------------


def check_ipc_safety(tool_name: str, tool_input: dict) -> None:
    """
    Enforces production IPC directory safety by blocking tool calls that reference "/tmp".
    
    Checks the JSON-serialized tool_input for the substring "/tmp" when running in production and, if found, issues a block decision citing PARROT_IPC_DIR. Parameters are described only to clarify their roles.
    
    Parameters:
        tool_name (str): Name of the tool invoking the check, used in block message.
        tool_input (dict): The tool's input payload to be inspected for disallowed IPC paths.
    """
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
    """
    Enforces that Parrot MCP tools may only run when an engagement is active.
    
    If the provided tool name identifies a Parrot MCP tool and the engagement flag is not active, this will block the invocation with a reason instructing to set PARROT_ENGAGEMENT_ACTIVE=1.
    
    Parameters:
        tool_name (str): The name of the tool being invoked.
    """
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
    """
    Enforces a deny-list for Bash commands.
    
    When invoked for the Bash tool, inspects the "command" entry in tool_input and blocks the call if the command matches any configured denied regular-expression patterns; otherwise does nothing.
    
    Parameters:
        tool_name (str): Name of the tool being executed.
        tool_input (dict): Mapping of tool arguments; expected to contain a "command" string to evaluate.
    """
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
    """
    Rejects MCP tool arguments that contain shell metacharacters.
    
    Inspects string-valued arguments for tools whose names start with a Parrot MCP prefix; if any value contains shell metacharacters, signals a block decision and exits the process.
    
    Parameters:
        tool_name (str): The invoked tool's name; checked against PARROT_MCP_PREFIXES to determine applicability.
        tool_input (dict): Mapping of argument names to values; string values are scanned for injection characters.
    """
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
    """
    Validate MCP tool argument shapes and sizes for safe JSON serialization.
    
    Applies only to tools whose name starts with any value in PARROT_MCP_PREFIXES.
    For each argument that is a list or dict, blocks the tool call if the value is not
    JSON-serializable or if its JSON-serialized representation exceeds 4096 bytes.
    
    Parameters:
        tool_name (str): Name of the tool being invoked.
        tool_input (dict): Mapping of argument names to their values; inspected for
            structured (list/dict) values that must be JSON-serializable and under
            the size limit.
    """
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
    """
    Run pre-tool-use security checks against a JSON event read from standard input.
    
    Reads a JSON event from stdin, extracts `tool_name` and `tool_input`, and runs the suite of enforcement checks in sequence (IPC directory safety, engagement gate, blocked command patterns, injection-character detection, and MCP argument shape validation). If any check fails the function signals a block and exits; if input is empty or invalid JSON the function allows the call, and if all checks pass the function allows the call and exits.
    """
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
