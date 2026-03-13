"""Parrot MCP Server — entry point.

FastMCP-based red/purple team orchestration server.

Transport: STDIO (default) — safe for local Kali/WSL2 use; does not open
           network ports.  Add `transport="sse"` to mcp.run() for remote
           clients, but only behind a VPN or mTLS gateway.

Tool categories registered here:
  1. Engagement management  (this file)
  2. Reconnaissance         (tools/recon.py)
  3. Web enumeration        (tools/web.py)
  4. Post-exploitation      (tools/post_exploit.py)
  5. Loot management        (loot.py — also exposes MCP Resources)

Usage:
  parrot-mcp                # via pyproject.toml entry point
  python -m parrot_mcp_server.server
"""
from __future__ import annotations

import sys
from datetime import datetime, timezone

from mcp.server.fastmcp import FastMCP

from parrot_mcp_server import __version__
from parrot_mcp_server.auth import (
    Engagement,
    engagement_fingerprint,
    register_engagement,
    require_authorization,
    _ACTIVE_ENGAGEMENTS,
)
from parrot_mcp_server import loot as loot_module
from parrot_mcp_server.tools import recon, web, post_exploit

# ---------------------------------------------------------------------------
# Server instance
# ---------------------------------------------------------------------------

mcp = FastMCP(
    name="parrot-mcp",
    instructions=(
        "Red/purple team MCP orchestration server v"
        + __version__
        + ". All tools require an active, in-scope engagement. "
        "Register one first with register_engagement_tool()."
    ),
)

# ---------------------------------------------------------------------------
# Engagement management tools
# ---------------------------------------------------------------------------


@mcp.tool()
def register_engagement_tool(
    engagement_id: str,
    scope: list[str],
    authorized_by: str,
    start_utc: str,
    end_utc: str,
    rules_of_engagement: str,
    teams: list[str] | None = None,
) -> str:
    """Register a new authorized pentesting engagement.

    This MUST be called before any active tool (scan, probe, harvest, etc.).
    All tool calls are gated against registered engagements for scope and
    time-window validation.

    Args:
        engagement_id: Unique identifier (e.g. 'ENG-2024-001').
        scope: List of in-scope targets — IPv4s, CIDRs, hostnames, or '*'
               for all.  Examples: ['192.168.1.0/24', 'app.example.com']
        authorized_by: Name/email of the officer who authorized this engagement.
        start_utc: ISO 8601 UTC start time (e.g. '2024-01-15T09:00:00+00:00').
        end_utc: ISO 8601 UTC end time (e.g. '2024-01-15T17:00:00+00:00').
        rules_of_engagement: Free-text RoE summary (documented for audit).
        teams: Optional list of team labels: 'red', 'purple', 'osint', etc.
    """
    try:
        start = datetime.fromisoformat(start_utc)
        end = datetime.fromisoformat(end_utc)
    except ValueError as exc:
        return (
            f"[ERROR] Invalid datetime format: {exc}\n"
            "Use ISO 8601: '2024-01-15T09:00:00+00:00'"
        )

    # Ensure datetimes are timezone-aware (default to UTC if naive)
    if start.tzinfo is None:
        start = start.replace(tzinfo=timezone.utc)
    if end.tzinfo is None:
        end = end.replace(tzinfo=timezone.utc)

    if end <= start:
        return "[ERROR] end_utc must be after start_utc."

    if not scope:
        return "[ERROR] scope must contain at least one entry."

    if not authorized_by.strip():
        return "[ERROR] authorized_by cannot be empty."

    eng = Engagement(
        engagement_id=engagement_id.strip(),
        scope=[s.strip() for s in scope],
        authorized_by=authorized_by.strip(),
        start_utc=start,
        end_utc=end,
        rules_of_engagement=rules_of_engagement.strip(),
        teams=teams or [],
    )

    register_engagement(eng)
    fp = engagement_fingerprint(eng)

    return (
        f"[ENGAGEMENT REGISTERED]\n"
        f"  ID          : {eng.engagement_id}\n"
        f"  Fingerprint : {fp}\n"
        f"  Authorized  : {eng.authorized_by}\n"
        f"  Window      : {eng.start_utc.isoformat()} → {eng.end_utc.isoformat()}\n"
        f"  Scope       : {', '.join(eng.scope)}\n"
        f"  Teams       : {', '.join(eng.teams) or 'unspecified'}\n"
        f"  RoE         : {eng.rules_of_engagement[:120]}"
    )


@mcp.tool()
def list_engagements() -> str:
    """List all currently registered engagements and their status.

    Shows whether each engagement window is active, expired, or not yet started.
    """
    if not _ACTIVE_ENGAGEMENTS:
        return (
            "[NO ENGAGEMENTS]\n"
            "Register one first with register_engagement_tool()."
        )

    now = datetime.now(tz=timezone.utc)
    lines = [f"[REGISTERED ENGAGEMENTS — {len(_ACTIVE_ENGAGEMENTS)} total]\n"]

    for eid, eng in _ACTIVE_ENGAGEMENTS.items():
        if now < eng.start_utc:
            status = "PENDING  (not yet started)"
        elif now > eng.end_utc:
            status = "EXPIRED"
        else:
            remaining = eng.end_utc - now
            hours = int(remaining.total_seconds() // 3600)
            mins = int((remaining.total_seconds() % 3600) // 60)
            status = f"ACTIVE   ({hours}h {mins}m remaining)"

        fp = engagement_fingerprint(eng)
        lines.append(
            f"  {eid}\n"
            f"    Status      : {status}\n"
            f"    Fingerprint : {fp}\n"
            f"    Authorized  : {eng.authorized_by}\n"
            f"    Window      : {eng.start_utc.isoformat()} → {eng.end_utc.isoformat()}\n"
            f"    Scope       : {', '.join(eng.scope)}\n"
            f"    Teams       : {', '.join(eng.teams) or 'unspecified'}\n"
        )

    return "\n".join(lines)


@mcp.tool()
def check_scope(engagement_id: str, target: str) -> str:
    """Check whether a specific target is in scope for an engagement.

    Useful before running a tool to verify authorization without triggering
    a full tool execution.

    Args:
        engagement_id: Engagement to check against.
        target: IP, CIDR, or hostname to verify.
    """
    try:
        eng = require_authorization(engagement_id, target.strip())
        fp = engagement_fingerprint(eng)
        return (
            f"[IN SCOPE]\n"
            f"  Target      : {target}\n"
            f"  Engagement  : {engagement_id}\n"
            f"  Fingerprint : {fp}\n"
            f"  Authorized  : {eng.authorized_by}\n"
            f"  Scope list  : {', '.join(eng.scope)}"
        )
    except PermissionError as exc:
        return f"[OUT OF SCOPE] {exc}"


@mcp.tool()
def server_info() -> str:
    """Return server version, available tool categories, and configuration."""
    from parrot_mcp_server.tools.validators import LOOT_DIR

    tool_count = len([attr for attr in dir(mcp) if not attr.startswith("_")])

    return (
        f"[PARROT MCP SERVER v{__version__}]\n"
        f"\n"
        f"  Transport    : STDIO (local execution)\n"
        f"  Loot dir     : {LOOT_DIR}\n"
        f"\n"
        f"  Tool categories:\n"
        f"    • Engagement management : register_engagement_tool, list_engagements,\n"
        f"                              check_scope\n"
        f"    • Reconnaissance        : nmap_scan, service_discovery, os_fingerprint,\n"
        f"                              host_discovery\n"
        f"    • Web enumeration       : http_probe, dir_scan, tech_detect\n"
        f"    • Post-exploitation     : credential_harvest, persistence_check,\n"
        f"                              privesc_check, ssh_key_audit\n"
        f"    • Loot management       : list_loot, read_loot, delete_loot\n"
        f"\n"
        f"  MCP Resources:\n"
        f"    loot://files            — list all collected artifacts\n"
        f"    loot://file/<name>      — read a specific artifact\n"
        f"\n"
        f"  Security notes:\n"
        f"    - All tools require register_engagement_tool() first.\n"
        f"    - All subprocess calls use list form (no shell injection).\n"
        f"    - Loot is stored in {LOOT_DIR} with mode 0o700/0o600.\n"
        f"    - IPC uses /tmp/mcp_*.json (set PARROT_IPC_DIR for production).\n"
    )


# ---------------------------------------------------------------------------
# Register tool modules
# ---------------------------------------------------------------------------

recon.register(mcp)
web.register(mcp)
post_exploit.register(mcp)
loot_module.register(mcp)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    """Start the Parrot MCP server on STDIO transport."""
    mcp.run()


if __name__ == "__main__":
    main()
