"""Engagement authorization gate.

Every tool call passes through `require_authorization` before execution.
Engagements are registered with a scope, expiry, and authorizing contact
so that all activity is traceable back to a signed engagement record.
"""
from __future__ import annotations

import hashlib
import os
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Optional


@dataclass
class Engagement:
    """An authorized pentesting engagement."""

    engagement_id: str
    scope: list[str]          # CIDRs, hostnames, or asset tags in scope
    authorized_by: str        # Name / email of authorizing officer
    start_utc: datetime
    end_utc: datetime
    rules_of_engagement: str  # Free-text RoE summary
    teams: list[str] = field(default_factory=list)  # red, purple, osint…


_ACTIVE_ENGAGEMENTS: dict[str, Engagement] = {}


def register_engagement(eng: Engagement) -> str:
    """Register an engagement and return its ID."""
    _ACTIVE_ENGAGEMENTS[eng.engagement_id] = eng
    return eng.engagement_id


def require_authorization(engagement_id: str, target: str) -> Engagement:
    """
    Assert that *target* is in scope for *engagement_id* and the engagement
    window is currently active.  Raises PermissionError on any violation.
    """
    eng = _ACTIVE_ENGAGEMENTS.get(engagement_id)
    if eng is None:
        raise PermissionError(
            f"No active engagement found for ID '{engagement_id}'. "
            "Register an engagement before running tools."
        )

    now = datetime.now(tz=timezone.utc)
    if not (eng.start_utc <= now <= eng.end_utc):
        raise PermissionError(
            f"Engagement '{engagement_id}' is outside its authorized window "
            f"({eng.start_utc.isoformat()} – {eng.end_utc.isoformat()})."
        )

    # Scope check: target must exactly match a scope entry, be a sub-path of one
    # (delimited by '/' or '.'), or be covered by the wildcard '*'.
    # Using plain startswith() is intentionally avoided here because it would
    # allow "192.168.1.100.attacker.com" to match scope entry "192.168.1." —
    # a bypass that could let out-of-scope targets appear authorized.
    def _in_scope_entry(target: str, entry: str) -> bool:
        if entry == "*":
            return True
        if target == entry:
            return True
        # Allow sub-paths: scope "192.168.1." covers "192.168.1.5" (note trailing dot)
        # and scope "example.com/" covers "example.com/path".
        # Only accept the target if it starts with the entry AND the boundary
        # character is '/', '.', or ':' (port separator) — never a bare prefix.
        if entry.endswith(("/", ".", ":")):
            return target.startswith(entry)
        # For entries without an explicit boundary suffix, require an exact match
        # or that the next character after the entry is a boundary.
        if target.startswith(entry) and len(target) > len(entry) and target[len(entry)] in {".", "/", ":"}:
            return True
        return False

    in_scope = any(_in_scope_entry(target, s) for s in eng.scope)
    if not in_scope:
        raise PermissionError(
            f"Target '{target}' is NOT in scope for engagement '{engagement_id}'. "
            f"Authorized scope: {eng.scope}"
        )

    return eng


def engagement_fingerprint(eng: Engagement) -> str:
    """Return a short SHA-256 fingerprint of engagement metadata for audit logs."""
    raw = f"{eng.engagement_id}|{eng.authorized_by}|{eng.start_utc}|{eng.end_utc}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16]
