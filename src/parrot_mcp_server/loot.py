"""Loot directory management — MCP Resources for collected pentest artifacts.

Exposes the loot directory as MCP Resources so LLM clients can browse and
read scan outputs, credential harvest reports, and other artifacts without
needing a separate tool call for each file.

Resources exposed:
  loot://files          — list all files in the loot directory (JSON)
  loot://file/{name}    — read a specific loot file by name
"""
from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import TYPE_CHECKING

from parrot_mcp_server.tools.validators import LOOT_DIR, ensure_loot_dir, validate_loot_filename

if TYPE_CHECKING:
    from mcp.server.fastmcp import FastMCP

# Cap on how many bytes of a single loot file to return to the LLM inline
_INLINE_READ_LIMIT = 128 * 1024  # 128 KB


def register(mcp: "FastMCP") -> None:
    """Register loot resources and management tools with the MCP server."""

    # ------------------------------------------------------------------
    # Resource: loot://files  — directory listing
    # ------------------------------------------------------------------

    @mcp.resource("loot://files")
    def list_loot_files() -> str:
        """List all files in the loot directory as a JSON array.

        Each entry contains:
        - name: bare filename
        - size_bytes: file size
        - modified_utc: ISO 8601 last-modified timestamp
        - uri: resource URI to read the file
        """
        loot_dir = ensure_loot_dir()
        entries = []

        for path in sorted(loot_dir.iterdir()):
            if not path.is_file():
                continue
            try:
                st = path.stat()
                entries.append(
                    {
                        "name": path.name,
                        "size_bytes": st.st_size,
                        "modified_utc": datetime.fromtimestamp(
                            st.st_mtime, tz=timezone.utc
                        ).isoformat(),
                        "uri": f"loot://file/{path.name}",
                    }
                )
            except OSError:
                continue

        return json.dumps(entries, indent=2)

    # ------------------------------------------------------------------
    # Resource: loot://file/{name}  — individual file contents
    # ------------------------------------------------------------------

    @mcp.resource("loot://file/{name}")
    def read_loot_file(name: str) -> str:
        """Return the contents of a loot file by name.

        The file must reside in the loot directory.  Path traversal attempts
        are rejected.  Files larger than 128 KB are truncated.

        Args:
            name: Bare filename (e.g. 'nmap_192_168_1_1_20240101T120000Z.xml').
        """
        try:
            path = validate_loot_filename(name)
        except ValueError as exc:
            return json.dumps({"error": str(exc)})

        if not path.exists():
            return json.dumps({"error": f"File not found in loot directory: '{name}'."})
        if not path.is_file():
            return json.dumps({"error": f"Not a regular file: '{name}'."})

        try:
            with path.open("rb") as fh:
                raw = fh.read(_INLINE_READ_LIMIT)
            truncated = path.stat().st_size > _INLINE_READ_LIMIT

            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("latin-1")

            if truncated:
                text += (
                    f"\n\n[... FILE TRUNCATED — showing first {_INLINE_READ_LIMIT} bytes "
                    f"of {path.stat().st_size} total bytes ...]"
                )
            return text
        except (PermissionError, OSError) as exc:
            return json.dumps({"error": f"Cannot read file: {exc}"})

    # ------------------------------------------------------------------
    # Tool: list_loot  — callable by the LLM as a tool (not just a resource)
    # ------------------------------------------------------------------

    @mcp.tool()
    def list_loot() -> str:
        """List all files collected in the loot directory.

        Returns a formatted table of loot files with their sizes and
        timestamps, plus the resource URI to read each one.
        """
        loot_dir = ensure_loot_dir()
        files = sorted(loot_dir.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
        files = [f for f in files if f.is_file()]

        if not files:
            return f"[LOOT DIRECTORY EMPTY]\n  Path: {loot_dir}\n  No artifacts collected yet."

        lines = [
            f"[LOOT DIRECTORY: {loot_dir}]",
            f"  {len(files)} file(s) collected",
            "",
            f"  {'NAME':<60} {'SIZE':>10}  MODIFIED (UTC)",
            f"  {'-'*60} {'-'*10}  {'-'*20}",
        ]
        for f in files:
            try:
                st = f.stat()
                mtime = datetime.fromtimestamp(st.st_mtime, tz=timezone.utc).strftime(
                    "%Y-%m-%d %H:%M:%S"
                )
                lines.append(f"  {f.name:<60} {st.st_size:>10,}  {mtime}")
            except OSError:
                continue

        lines.append(
            "\nUse read_loot(filename) or the MCP resource loot://file/<name> to retrieve contents."
        )
        return "\n".join(lines)

    # ------------------------------------------------------------------
    # Tool: read_loot  — callable by the LLM as a tool
    # ------------------------------------------------------------------

    @mcp.tool()
    def read_loot(filename: str) -> str:
        """Read the contents of a file from the loot directory.

        Args:
            filename: Bare filename (e.g. 'nmap_192_168_1_1_20240101T120000Z.xml').
                      Must not contain path separators.
        """
        try:
            path = validate_loot_filename(filename)
        except ValueError as exc:
            return f"[ERROR] {exc}"

        if not path.exists():
            return f"[ERROR] File not found in loot directory: '{filename}'.\nUse list_loot() to see available files."

        try:
            with path.open("rb") as fh:
                raw = fh.read(_INLINE_READ_LIMIT)
            size = path.stat().st_size
            truncated = size > _INLINE_READ_LIMIT

            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = raw.decode("latin-1")

            header = (
                f"[LOOT FILE: {filename}]\n"
                f"  Size: {size:,} bytes"
                + (" (truncated)" if truncated else "")
                + "\n\n"
            )
            footer = (
                f"\n\n[... truncated at {_INLINE_READ_LIMIT:,} bytes ...]"
                if truncated
                else ""
            )
            return header + text + footer
        except (PermissionError, OSError) as exc:
            return f"[ERROR] Cannot read file: {exc}"

    # ------------------------------------------------------------------
    # Tool: delete_loot  — clean up old artifacts
    # ------------------------------------------------------------------

    @mcp.tool()
    def delete_loot(filename: str) -> str:
        """Delete a specific file from the loot directory.

        Args:
            filename: Bare filename to delete (must not contain path separators).
        """
        try:
            path = validate_loot_filename(filename)
        except ValueError as exc:
            return f"[ERROR] {exc}"

        if not path.exists():
            return f"[ERROR] File not found: '{filename}'."

        try:
            path.unlink()
            return f"[OK] Deleted: {filename}"
        except OSError as exc:
            return f"[ERROR] Could not delete '{filename}': {exc}"
