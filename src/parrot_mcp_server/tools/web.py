"""Web enumeration and HTTP probing tools for the Parrot MCP server.

Tools:
- http_probe   — send a single HTTP/S request and inspect the response
- dir_scan     — directory/file enumeration via gobuster or ffuf
- tech_detect  — basic technology stack fingerprinting
"""
from __future__ import annotations

import shutil
import subprocess
from datetime import datetime, timezone
from typing import TYPE_CHECKING

import httpx

from parrot_mcp_server.auth import engagement_fingerprint, require_authorization
from parrot_mcp_server.tools.validators import (
    ensure_loot_dir,
    validate_extensions,
    validate_http_method,
    validate_port_number,
    validate_target,
    validate_url_path,
    validate_wordlist_path,
)

if TYPE_CHECKING:
    from mcp.server.fastmcp import FastMCP

_HTTP_TIMEOUT = 30
_DIR_SCAN_TIMEOUT = 600

# Preview cap for HTTP response bodies sent back to the LLM
_BODY_PREVIEW_BYTES = 4096


def _ts() -> str:
    return datetime.now(tz=timezone.utc).strftime("%Y%m%dT%H%M%SZ")


def _safe_name(s: str) -> str:
    return s.replace(".", "_").replace("/", "_").replace(":", "_")


def register(mcp: "FastMCP") -> None:
    """Register all web tools with the MCP server instance."""

    # ------------------------------------------------------------------
    # http_probe
    # ------------------------------------------------------------------

    @mcp.tool()
    def http_probe(
        engagement_id: str,
        target: str,
        port: int = 80,
        path: str = "/",
        method: str = "GET",
        use_tls: bool = False,
        follow_redirects: bool = True,
        post_body: str = "",
    ) -> str:
        """Probe an HTTP/HTTPS endpoint and return status, headers, and a body preview.

        Useful for:
        - Banner grabbing / technology fingerprinting
        - Checking for default credentials pages
        - Validating redirect chains
        - Testing specific endpoints during web app assessment

        Args:
            engagement_id: Active engagement ID.
            target: Hostname or IPv4 address.
            port: TCP port (default: 80).
            path: URL path including query string (default: '/').
            method: HTTP method — GET, HEAD, POST, OPTIONS, PUT, DELETE
                    (default: 'GET').
            use_tls: Use HTTPS (default: False).
            follow_redirects: Follow 3xx redirects (default: True).
            post_body: Request body for POST/PUT requests (default: '').
        """
        try:
            t = validate_target(target)
            p = validate_port_number(port)
            url_path = validate_url_path(path)
            meth = validate_http_method(method)
        except ValueError as exc:
            return f"[ERROR] Input validation: {exc}"

        try:
            eng = require_authorization(engagement_id, t)
        except PermissionError as exc:
            return f"[AUTH DENIED] {exc}"

        scheme = "https" if use_tls else "http"
        url = f"{scheme}://{t}:{p}{url_path}"

        try:
            with httpx.Client(verify=False, timeout=_HTTP_TIMEOUT) as client:
                resp = client.request(
                    meth,
                    url,
                    follow_redirects=follow_redirects,
                    content=post_body.encode() if post_body else None,
                    headers={
                        "User-Agent": "Mozilla/5.0 (compatible; ParrotMCP/1.0)",
                    },
                )

            headers_lines = "\n".join(
                f"  {k}: {v}" for k, v in resp.headers.items()
            )
            body_text = resp.text[:_BODY_PREVIEW_BYTES]
            truncated = (
                f"\n  [... truncated at {_BODY_PREVIEW_BYTES} bytes ...]"
                if len(resp.text) > _BODY_PREVIEW_BYTES
                else ""
            )

            probe_result = (
                f"URL    : {url}\n"
                f"Status : {resp.status_code} {resp.reason_phrase}\n"
                f"Headers:\n{headers_lines}\n\n"
                f"Body preview:\n{body_text}{truncated}"
            )

        except httpx.ConnectError as exc:
            probe_result = f"[CONNECTION ERROR] Could not reach {url}: {exc}"
        except httpx.TimeoutException:
            probe_result = f"[TIMEOUT] Request to {url} exceeded {_HTTP_TIMEOUT}s."
        except httpx.RequestError as exc:
            probe_result = f"[REQUEST ERROR] {exc}"

        # Persist full result to loot
        loot_dir = ensure_loot_dir()
        loot_file = loot_dir / f"http_probe_{_safe_name(t)}_{p}_{_ts()}.txt"
        loot_file.write_text(probe_result, encoding="utf-8")
        loot_file.chmod(0o600)

        fp = engagement_fingerprint(eng)
        return (
            f"[HTTP PROBE]\n"
            f"  Engagement : {engagement_id}  (fingerprint: {fp})\n"
            f"  Loot file  : {loot_file}\n\n"
            f"{probe_result}"
        )

    # ------------------------------------------------------------------
    # dir_scan
    # ------------------------------------------------------------------

    @mcp.tool()
    def dir_scan(
        engagement_id: str,
        target: str,
        port: int = 80,
        wordlist: str = "/usr/share/wordlists/dirb/common.txt",
        extensions: str = "php,html,txt,js",
        use_tls: bool = False,
        threads: int = 50,
    ) -> str:
        """Directory and file enumeration using gobuster (preferred) or ffuf.

        Attempts to find hidden paths, admin panels, backup files, and API
        endpoints.  Requires gobuster or ffuf to be installed.

        Args:
            engagement_id: Active engagement ID.
            target: Hostname or IPv4 address.
            port: TCP port (default: 80).
            wordlist: Absolute path to a wordlist file.
                      Default: /usr/share/wordlists/dirb/common.txt
            extensions: Comma-separated file extensions to append.
                        Default: 'php,html,txt,js'
            use_tls: Use HTTPS (default: False).
            threads: Concurrent request threads (default: 50, max: 200).
        """
        try:
            t = validate_target(target)
            p = validate_port_number(port)
            wl = validate_wordlist_path(wordlist)
            ext = validate_extensions(extensions)
        except ValueError as exc:
            return f"[ERROR] Input validation: {exc}"

        if not (1 <= threads <= 200):
            return "[ERROR] threads must be between 1 and 200."

        try:
            eng = require_authorization(engagement_id, t)
        except PermissionError as exc:
            return f"[AUTH DENIED] {exc}"

        scheme = "https" if use_tls else "http"
        base_url = f"{scheme}://{t}:{p}/"

        loot_dir = ensure_loot_dir()
        loot_file = loot_dir / f"dirscan_{_safe_name(t)}_{p}_{_ts()}.txt"

        # Select tool: gobuster > ffuf > error
        gobuster = shutil.which("gobuster")
        ffuf = shutil.which("ffuf")

        if gobuster:
            cmd = [
                gobuster, "dir",
                "-u", base_url,
                "-w", str(wl),
                "-x", ext,
                "-o", str(loot_file),
                "-t", str(threads),
                "--timeout", "10s",
                "-q",  # quiet — suppress banner
            ]
            tool_name = "gobuster"
        elif ffuf:
            cmd = [
                ffuf,
                "-u", f"{base_url}FUZZ",
                "-w", str(wl),
                "-e", "." + ext.replace(",", ",."),
                "-o", str(loot_file),
                "-of", "json",
                "-t", str(threads),
                "-timeout", "10",
                "-s",  # silent — suppress banner
            ]
            tool_name = "ffuf"
        else:
            return (
                "[ERROR] No directory scanner found. Install one with:\n"
                "  sudo apt-get install gobuster      # Kali/Debian\n"
                "  go install github.com/ffuf/ffuf@latest"
            )

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=_DIR_SCAN_TIMEOUT,
            )
        except subprocess.TimeoutExpired:
            return f"[ERROR] Directory scan timed out after {_DIR_SCAN_TIMEOUT}s."

        output = (result.stdout or result.stderr or "").strip()

        # If loot file wasn't written by the tool, persist stdout ourselves
        if not loot_file.exists():
            loot_file.write_text(output, encoding="utf-8")
            loot_file.chmod(0o600)

        fp = engagement_fingerprint(eng)
        return (
            f"[DIR SCAN]\n"
            f"  Tool       : {tool_name}\n"
            f"  Engagement : {engagement_id}  (fingerprint: {fp})\n"
            f"  Target     : {base_url}\n"
            f"  Wordlist   : {wl}\n"
            f"  Extensions : {ext}\n"
            f"  Threads    : {threads}\n"
            f"  Loot file  : {loot_file}\n\n"
            f"{output[:4096]}"
        )

    # ------------------------------------------------------------------
    # tech_detect
    # ------------------------------------------------------------------

    @mcp.tool()
    def tech_detect(
        engagement_id: str,
        target: str,
        port: int = 80,
        use_tls: bool = False,
    ) -> str:
        """Fingerprint the technology stack of a web server.

        Inspects:
        - Server and X-Powered-By headers
        - Set-Cookie header patterns (session cookie names)
        - Common framework indicators in response body
        - Security headers presence/absence

        Args:
            engagement_id: Active engagement ID.
            target: Hostname or IPv4 address.
            port: TCP port (default: 80).
            use_tls: Use HTTPS (default: False).
        """
        try:
            t = validate_target(target)
            p = validate_port_number(port)
        except ValueError as exc:
            return f"[ERROR] {exc}"

        try:
            eng = require_authorization(engagement_id, t)
        except PermissionError as exc:
            return f"[AUTH DENIED] {exc}"

        scheme = "https" if use_tls else "http"
        urls_to_probe = [
            f"{scheme}://{t}:{p}/",
            f"{scheme}://{t}:{p}/robots.txt",
            f"{scheme}://{t}:{p}/sitemap.xml",
        ]

        findings: list[str] = []
        security_headers = [
            "strict-transport-security",
            "content-security-policy",
            "x-frame-options",
            "x-content-type-options",
            "x-xss-protection",
            "referrer-policy",
            "permissions-policy",
        ]

        try:
            with httpx.Client(verify=False, timeout=_HTTP_TIMEOUT) as client:
                for url in urls_to_probe:
                    try:
                        resp = client.get(
                            url,
                            follow_redirects=True,
                            headers={"User-Agent": "Mozilla/5.0"},
                        )
                    except (httpx.RequestError, httpx.TimeoutException):
                        continue

                    if url.endswith("/"):
                        # Technology indicators
                        server = resp.headers.get("server", "")
                        powered = resp.headers.get("x-powered-by", "")
                        cookie_hdr = resp.headers.get("set-cookie", "")

                        findings.append(f"\n=== {url} (HTTP {resp.status_code}) ===")
                        if server:
                            findings.append(f"  Server        : {server}")
                        if powered:
                            findings.append(f"  X-Powered-By  : {powered}")
                        if cookie_hdr:
                            findings.append(f"  Set-Cookie    : {cookie_hdr[:120]}")

                        # Security header audit
                        findings.append("\n  Security Headers:")
                        for sh in security_headers:
                            val = resp.headers.get(sh, "MISSING")
                            flag = "✓" if val != "MISSING" else "✗"
                            findings.append(f"    [{flag}] {sh}: {val[:80]}")

                        # Framework detection via body patterns
                        body = resp.text[:8192].lower()
                        frameworks: list[str] = []
                        _fw_patterns = {
                            "WordPress": "wp-content",
                            "Drupal": "drupal.js",
                            "Joomla": "joomla",
                            "Laravel": "laravel",
                            "Django": "csrfmiddlewaretoken",
                            "React": "react.development",
                            "Vue.js": "vue.min.js",
                            "Angular": "ng-version",
                            "jQuery": "jquery",
                            "Bootstrap": "bootstrap.min.css",
                        }
                        for fw, sig in _fw_patterns.items():
                            if sig in body:
                                frameworks.append(fw)
                        if frameworks:
                            findings.append(f"\n  Detected frameworks: {', '.join(frameworks)}")

                    elif url.endswith("robots.txt") and resp.status_code == 200:
                        findings.append(f"\n=== robots.txt ===\n{resp.text[:512]}")

        except httpx.RequestError as exc:
            findings.append(f"[REQUEST ERROR] {exc}")

        report = "\n".join(findings) if findings else "[No findings]"

        loot_dir = ensure_loot_dir()
        loot_file = loot_dir / f"tech_detect_{_safe_name(t)}_{p}_{_ts()}.txt"
        loot_file.write_text(report, encoding="utf-8")
        loot_file.chmod(0o600)

        fp = engagement_fingerprint(eng)
        return (
            f"[TECH DETECT]\n"
            f"  Engagement : {engagement_id}  (fingerprint: {fp})\n"
            f"  Target     : {scheme}://{t}:{p}/\n"
            f"  Loot file  : {loot_file}\n"
            f"{report}"
        )
