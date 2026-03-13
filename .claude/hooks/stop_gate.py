#!/usr/bin/env python3
"""
Stop-gate: weighted risk-scoring final trust boundary for Parrot MCP Server.

Reads the full session audit trail produced by post_tool_use.py and accumulates
a risk score using configurable event weights.  If the cumulative score exceeds
PARROT_STOP_GATE_THRESHOLD the session is rejected (exit 2) and no changes land.

Risk score weights (env-overridable):
  WEIGHT_SECRET_LEAK        default 40  — secret pattern matched in output
  WEIGHT_OUT_OF_SCOPE       default 30  — IP address outside declared scope
  WEIGHT_BLOCKED            default 25  — pre-hook hard-blocked a tool call
  WEIGHT_CLEAN_CREDIT       default -1  — per allowed event (credit toward clean)

PARROT_STOP_GATE_THRESHOLD  default 100

Exit codes:
  0  — session approved; proceed
  2  — session rejected; accumulated risk score exceeds threshold
"""

import json
import os
import sys
from pathlib import Path

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LOG_DIR = Path(os.environ.get("PARROT_LOG_DIR", "/var/log/parrot"))
SESSION_ID = os.environ.get("PARROT_SESSION_ID", "unknown")
AUDIT_LOG = LOG_DIR / f"audit_{SESSION_ID}.jsonl"

THRESHOLD = int(os.environ.get("PARROT_STOP_GATE_THRESHOLD", "100"))

WEIGHT_SECRET_LEAK  = int(os.environ.get("WEIGHT_SECRET_LEAK",  "40"))
WEIGHT_OUT_OF_SCOPE = int(os.environ.get("WEIGHT_OUT_OF_SCOPE", "30"))
WEIGHT_BLOCKED      = int(os.environ.get("WEIGHT_BLOCKED",      "25"))
WEIGHT_CLEAN_CREDIT = int(os.environ.get("WEIGHT_CLEAN_CREDIT", "-1"))


# ---------------------------------------------------------------------------
# Audit log reader
# ---------------------------------------------------------------------------


def _load_audit_entries() -> list[dict]:
    entries: list[dict] = []
    if not AUDIT_LOG.exists():
        return entries
    try:
        with AUDIT_LOG.open() as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    entries.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    except OSError:
        pass
    return entries


# ---------------------------------------------------------------------------
# Scoring
# ---------------------------------------------------------------------------


def _score_session(entries: list[dict]) -> tuple[int, list[str]]:
    score = 0
    reasons: list[str] = []

    for entry in entries:
        tool = entry.get("tool_name", "unknown")
        ts   = entry.get("ts", 0)

        if entry.get("secret_leak_detected"):
            patterns = entry.get("secret_patterns_matched", [])
            score += WEIGHT_SECRET_LEAK
            reasons.append(
                f"[+{WEIGHT_SECRET_LEAK}] Secret leak in '{tool}' "
                f"(patterns: {', '.join(patterns)}) @ ts={ts:.0f}"
            )

        if entry.get("out_of_scope_detected"):
            ips = entry.get("scope_drift", {}).get("out_of_scope_ips", [])
            score += WEIGHT_OUT_OF_SCOPE
            reasons.append(
                f"[+{WEIGHT_OUT_OF_SCOPE}] Out-of-scope IPs in '{tool}': "
                f"{ips} @ ts={ts:.0f}"
            )

        if entry.get("blocked"):
            score += WEIGHT_BLOCKED
            reasons.append(
                f"[+{WEIGHT_BLOCKED}] Tool '{tool}' was hard-blocked @ ts={ts:.0f}"
            )

        # Clean event credit — only if none of the above triggered
        if (
            not entry.get("secret_leak_detected")
            and not entry.get("out_of_scope_detected")
            and not entry.get("blocked")
        ):
            score += WEIGHT_CLEAN_CREDIT  # typically -1

    return score, reasons


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    entries = _load_audit_entries()

    if not entries:
        # No audit data — allow (nothing happened to score)
        sys.exit(0)

    score, reasons = _score_session(entries)

    print(
        f"[STOP-GATE] Session '{SESSION_ID}' risk score: {score} "
        f"(threshold: {THRESHOLD}, events: {len(entries)})"
    )

    if reasons:
        for r in reasons:
            print(f"  {r}")

    if score >= THRESHOLD:
        print(
            f"\n[STOP-GATE] REJECTED — risk score {score} >= threshold {THRESHOLD}. "
            "Session changes will not be applied."
        )
        sys.exit(2)

    print(f"\n[STOP-GATE] APPROVED — risk score {score} < threshold {THRESHOLD}.")
    sys.exit(0)


if __name__ == "__main__":
    main()
