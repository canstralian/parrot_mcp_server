"""Network reconnaissance tools for the Parrot MCP server.

All tools:
- Require an active, in-scope engagement via require_authorization()
- Use list-form subprocess calls (no shell=True, no f-string injection)
- Write raw output to the loot directory at loot/<scan-type>_<target>_<ts>.*
"""
from __future__ import annotations

import subprocess
from datetime import datetime, timezone
from typing import TYPE_CHECKING

from parrot_mcp_server.auth import engagement_fingerprint, require_authorization
from parrot_mcp_server.tools.validators import (
    ensure_loot_dir,
    validate_ports,
    validate_target,
)

if TYPE_CHECKING:
    from mcp.server.fastmcp import FastMCP


# Allowed nmap flag tokens — never pass arbitrary user strings to nmap
_SAFE_NMAP_FLAGS: frozenset[str] = frozenset(
    {"-sV", "-sS", "-sU", "-sT", "-sn", "-O", "-sC", "-A"}
)

# Maximum scan duration (seconds) — prevent runaway long-running scans
_SCAN_TIMEOUT = 300


def _ts() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _safe_name(target: str) -> str:
    """Convert target to a safe filename fragment."""
    return target.replace("/", "_").replace(".", "_").replace(":", "_")


def register(mcp: "FastMCP") -> None:
    """Register all reconnaissance tools with the MCP server instance."""

    # ------------------------------------------------------------------
    # nmap_scan
    # ------------------------------------------------------------------

    @mcp.tool()
    def nmap_scan(
        engagement_id: str,
        target: str,
        ports: str = "top100",
        scan_flags: str = "-sV",
        timing: str = "T3",
    ) -> str:
        """Run an nmap port scan and save XML output to the loot directory.

        Args:
            engagement_id: Active engagement ID (must be registered first).
            target: IPv4 address, CIDR block, or hostname to scan.
            ports: Port specification — 'top100', 'top1000', '80,443', or
                   a range like '1-1024'.  Default: 'top100'.
            scan_flags: Space-separated nmap flags from the allowed set:
                        -sV -sS -sU -sT -sn -O -sC -A.  Default: '-sV'.
            timing: nmap timing template T0–T5 (T3=normal, T4=aggressive).
                    Default: 'T3'.
        """
        # --- Validate inputs ---
        try:
            t = validate_target(target)
            p = validate_ports(ports)
        except ValueError as exc:
            return f"[ERROR] Input validation failed: {exc}"

        # Timing template must be T0–T5
        if timing not in {"T0", "T1", "T2", "T3", "T4", "T5"}:
            return "[ERROR] timing must be one of T0–T5."

        # Filter flag tokens against allowlist
        requested_flags = scan_flags.split()
        flag_list = [f for f in requested_flags if f in _SAFE_NMAP_FLAGS]
        if not flag_list:
            flag_list = ["-sV"]

        # --- Authorization gate ---
        try:
            eng = require_authorization(engagement_id, t)
        except PermissionError as exc:
            return f"[AUTH DENIED] {exc}"

        # --- Build command (list form — no shell injection possible) ---
        cmd = ["nmap", f"-{timing}"]
        cmd.extend(flag_list)

        if p == "top100":
            cmd += ["--top-ports", "100"]
        elif p == "top1000":
            cmd += ["--top-ports", "1000"]
        elif p != "-":
            cmd += ["-p", p]

        # Request XML to stdout for structured parsing
        cmd += ["-oX", "-", t]

        # --- Execute ---
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=_SCAN_TIMEOUT,
            )
        except FileNotFoundError:
            return (
                "[ERROR] nmap not found. Install with:\n"
                "  sudo apt-get install nmap  # Debian/Ubuntu/Kali\n"
                "  brew install nmap          # macOS"
            )
        except subprocess.TimeoutExpired:
            return f"[ERROR] Scan timed out after {_SCAN_TIMEOUT}s."

        # --- Persist loot ---
        loot_dir = ensure_loot_dir()
        loot_file = loot_dir / f"nmap_{_safe_name(t)}_{_ts()}.xml"
        output = result.stdout or result.stderr
        if output:
            loot_file.write_text(output, encoding="utf-8")
            loot_file.chmod(0o600)

        fp = engagement_fingerprint(eng)
        return (
            f"[NMAP SCAN COMPLETE]\n"
            f"  Engagement : {engagement_id}  (fingerprint: {fp})\n"
            f"  Target     : {t}\n"
            f"  Ports      : {p}\n"
            f"  Flags      : {' '.join(flag_list)}\n"
            f"  Loot file  : {loot_file}\n"
            f"\n{output}"
        )

    # ------------------------------------------------------------------
    # service_discovery
    # ------------------------------------------------------------------

    @mcp.tool()
    def service_discovery(
        engagement_id: str,
        target: str,
        ports: str = "top1000",
        intensity: int = 7,
    ) -> str:
        """Deep service version detection using nmap -sV --version-intensity.

        Args:
            engagement_id: Active engagement ID.
            target: IPv4 address, CIDR, or hostname.
            ports: Port specification (default: 'top1000').
            intensity: nmap --version-intensity 0–9 (default: 7).
        """
        try:
            t = validate_target(target)
            p = validate_ports(ports)
        except ValueError as exc:
            return f"[ERROR] {exc}"

        if not (0 <= intensity <= 9):
            return "[ERROR] intensity must be 0–9."

        try:
            eng = require_authorization(engagement_id, t)
        except PermissionError as exc:
            return f"[AUTH DENIED] {exc}"

        cmd = ["nmap", "-sV", "--version-intensity", str(intensity), "-T4"]

        if p == "top1000":
            cmd += ["--top-ports", "1000"]
        elif p == "top100":
            cmd += ["--top-ports", "100"]
        elif p != "-":
            cmd += ["-p", p]

        cmd.append(t)

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=_SCAN_TIMEOUT
            )
        except FileNotFoundError:
            return "[ERROR] nmap not found."
        except subprocess.TimeoutExpired:
            return f"[ERROR] Service discovery timed out after {_SCAN_TIMEOUT}s."

        output = result.stdout or result.stderr

        loot_dir = ensure_loot_dir()
        loot_file = loot_dir / f"svcdisco_{_safe_name(t)}_{_ts()}.txt"
        loot_file.write_text(output, encoding="utf-8")
        loot_file.chmod(0o600)

        fp = engagement_fingerprint(eng)
        return (
            f"[SERVICE DISCOVERY]\n"
            f"  Engagement  : {engagement_id}  (fingerprint: {fp})\n"
            f"  Target      : {t}\n"
            f"  Ports       : {p}\n"
            f"  Intensity   : {intensity}\n"
            f"  Loot file   : {loot_file}\n"
            f"\n{output}"
        )

    # ------------------------------------------------------------------
    # os_fingerprint
    # ------------------------------------------------------------------

    @mcp.tool()
    def os_fingerprint(
        engagement_id: str,
        target: str,
    ) -> str:
        """Attempt OS detection via nmap -O --osscan-guess.

        Note: OS detection requires raw socket privileges (root or CAP_NET_RAW).

        Args:
            engagement_id: Active engagement ID.
            target: IPv4 address or hostname to fingerprint.
        """
        try:
            t = validate_target(target)
        except ValueError as exc:
            return f"[ERROR] {exc}"

        try:
            eng = require_authorization(engagement_id, t)
        except PermissionError as exc:
            return f"[AUTH DENIED] {exc}"

        cmd = ["nmap", "-O", "--osscan-guess", "-T4", t]

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=120
            )
        except FileNotFoundError:
            return "[ERROR] nmap not found."
        except subprocess.TimeoutExpired:
            return "[ERROR] OS fingerprint timed out after 120s."

        output = result.stdout or result.stderr

        loot_dir = ensure_loot_dir()
        loot_file = loot_dir / f"os_fp_{_safe_name(t)}_{_ts()}.txt"
        loot_file.write_text(output, encoding="utf-8")
        loot_file.chmod(0o600)

        fp = engagement_fingerprint(eng)
        return (
            f"[OS FINGERPRINT]\n"
            f"  Engagement : {engagement_id}  (fingerprint: {fp})\n"
            f"  Target     : {t}\n"
            f"  Loot file  : {loot_file}\n"
            f"\n{output}"
        )

    # ------------------------------------------------------------------
    # host_discovery
    # ------------------------------------------------------------------

    @mcp.tool()
    def host_discovery(
        engagement_id: str,
        cidr: str,
    ) -> str:
        """Ping sweep a CIDR to discover live hosts (nmap -sn).

        Args:
            engagement_id: Active engagement ID (scope must include the CIDR).
            cidr: IPv4 CIDR block to sweep (e.g. '192.168.1.0/24').
        """
        try:
            t = validate_target(cidr)
        except ValueError as exc:
            return f"[ERROR] {exc}"

        try:
            eng = require_authorization(engagement_id, t)
        except PermissionError as exc:
            return f"[AUTH DENIED] {exc}"

        cmd = ["nmap", "-sn", "-T4", "--open", t]

        try:
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=180
            )
        except FileNotFoundError:
            return "[ERROR] nmap not found."
        except subprocess.TimeoutExpired:
            return "[ERROR] Host discovery timed out after 180s."

        output = result.stdout or result.stderr

        loot_dir = ensure_loot_dir()
        loot_file = loot_dir / f"host_disc_{_safe_name(t)}_{_ts()}.txt"
        loot_file.write_text(output, encoding="utf-8")
        loot_file.chmod(0o600)

        fp = engagement_fingerprint(eng)
        return (
            f"[HOST DISCOVERY]\n"
            f"  Engagement : {engagement_id}  (fingerprint: {fp})\n"
            f"  CIDR       : {t}\n"
            f"  Loot file  : {loot_file}\n"
            f"\n{output}"
        )
