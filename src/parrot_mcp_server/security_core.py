"""Security Core — Adaptive Immunity middleware for the Parrot MCP Server.

Two-layer threat model mirrors biological immunity:

  Innate layer  — fast, static rules; blocks known-bad patterns immediately.
  Adaptive layer — per-endpoint baseline tracking; anomaly score rises when
                   request characteristics deviate from the learned baseline.
                   The threshold tightens automatically when the system is
                   under active pressure (high anomaly rate).

Request lifecycle:
    [Flask Request]
          |
    {InnateGuard.check(req)}  -- known-bad patterns --> BLOCK (403)
          |
    {AdaptiveGuard.score(req)} -- score > threshold  --> QUARANTINE (429)
          |
         PASS --> handler

Quarantined sources are tracked with a TTL; after expiry they re-enter
the adaptive scoring pool rather than being permanently blocked.
"""
from __future__ import annotations

import json
import logging
import re
import time
from collections import deque
from dataclasses import dataclass, field
from enum import Enum, auto
from pathlib import Path
from typing import Callable

from pydantic import BaseModel, Field

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

_DEFAULT_PARAMS_PATH = Path(__file__).parent.parent.parent / "params.json"


def _load_security_params(params_path: Path = _DEFAULT_PARAMS_PATH) -> dict:  # type: ignore[type-arg]
    """Load security_core section from params.json; fall back to safe defaults."""
    try:
        with params_path.open() as fh:
            return json.load(fh).get("security_core", {})
    except (FileNotFoundError, json.JSONDecodeError):
        logger.warning("[msgid:%d] SecurityCore: params.json not found or invalid; using defaults", time.time_ns())
        return {}


# ---------------------------------------------------------------------------
# Domain models
# ---------------------------------------------------------------------------


class ThreatVector(Enum):
    """Categories of detected anomalies."""
    NONE = auto()
    PATH_TRAVERSAL = auto()
    INJECTION = auto()          # SQL / command / template injection patterns
    XSS = auto()
    OVERSIZED_HEADER = auto()
    EXCESSIVE_DEPTH = auto()    # Abnormally deep URL path
    RATE_ANOMALY = auto()       # Request rate outside baseline
    PAYLOAD_ANOMALY = auto()    # Payload size outside baseline


class RequestProfile(BaseModel):
    """Pydantic-validated snapshot of a single HTTP request for scoring."""

    source_ip: str = Field(..., description="Client IP address")
    method: str = Field(..., description="HTTP method")
    path: str = Field(..., description="Request path (URL-decoded)")
    path_depth: int = Field(0, ge=0, description="Number of path segments")
    content_length: int = Field(0, ge=0, description="Content-Length header value")
    header_size: int = Field(0, ge=0, description="Sum of all header bytes")
    engagement_id: str = Field("", description="Engagement ID from auth header, if present")
    timestamp_ns: int = Field(default_factory=time.time_ns)


@dataclass
class ThreatResult:
    """Outcome of a security check."""

    allowed: bool
    score: float                        # 0.0 (clean) – 1.0 (definite threat)
    vector: ThreatVector = ThreatVector.NONE
    reason: str = ""
    profile: RequestProfile | None = None


# ---------------------------------------------------------------------------
# Innate guard — static pattern matching
# ---------------------------------------------------------------------------

# Compiled once at import time for performance.
_INJECTION_RE = re.compile(
    r"(?:'|\"|`)\s*(or|and|union|select|insert|drop|update|delete|exec)\b",
    re.IGNORECASE,
)
_XSS_RE = re.compile(r"<\s*script|javascript\s*:|on\w+\s*=", re.IGNORECASE)
_TRAVERSAL_RE = re.compile(r"(\.\.[/\\]|%2e%2e[/\\%])", re.IGNORECASE)
_SENSITIVE_PATH_RE = re.compile(
    r"(/etc/passwd|/etc/shadow|/proc/self|/dev/null|/bin/sh)",
    re.IGNORECASE,
)


class InnateGuard:
    """Fast, stateless pattern-matching layer.

    Checks are O(1) per pattern — no state, no learning.  If any check fires
    the request is blocked immediately; adaptive scoring is not consulted.
    """

    def __init__(self, max_header_size: int = 8192, max_path_depth: int = 10) -> None:
        self._max_header = max_header_size
        self._max_depth = max_path_depth

    def check(self, profile: RequestProfile) -> ThreatResult:
        """Return a ThreatResult; allowed=False means block the request."""

        # --- structural checks -------------------------------------------------
        if profile.header_size > self._max_header:
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.OVERSIZED_HEADER,
                reason=f"Header size {profile.header_size}B exceeds limit {self._max_header}B",
                profile=profile,
            )

        if profile.path_depth > self._max_depth:
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.EXCESSIVE_DEPTH,
                reason=f"Path depth {profile.path_depth} exceeds limit {self._max_depth}",
                profile=profile,
            )

        # --- pattern checks ----------------------------------------------------
        search_target = profile.path

        if _TRAVERSAL_RE.search(search_target) or _SENSITIVE_PATH_RE.search(search_target):
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.PATH_TRAVERSAL,
                reason=f"Path traversal pattern detected in: {profile.path!r}",
                profile=profile,
            )

        if _INJECTION_RE.search(search_target):
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.INJECTION,
                reason="SQL/command injection pattern detected",
                profile=profile,
            )

        if _XSS_RE.search(search_target):
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.XSS,
                reason="XSS pattern detected",
                profile=profile,
            )

        return ThreatResult(allowed=True, score=0.0, profile=profile)


# ---------------------------------------------------------------------------
# Adaptive guard — per-endpoint baseline scoring
# ---------------------------------------------------------------------------


@dataclass
class _EndpointBaseline:
    """Rolling statistics for a single (method, path) pair."""

    window_seconds: float
    min_samples: int

    # circular buffers: (timestamp_ns, content_length)
    _samples: deque[tuple[int, int]] = field(default_factory=deque)
    _anomaly_timestamps: deque[int] = field(default_factory=deque)

    def _evict_stale(self, now_ns: int) -> None:
        cutoff_ns = now_ns - int(self.window_seconds * 1e9)
        while self._samples and self._samples[0][0] < cutoff_ns:
            self._samples.popleft()
        while self._anomaly_timestamps and self._anomaly_timestamps[0] < cutoff_ns:
            self._anomaly_timestamps.popleft()

    def record(self, timestamp_ns: int, content_length: int) -> None:
        self._evict_stale(timestamp_ns)
        self._samples.append((timestamp_ns, content_length))

    def record_anomaly(self, timestamp_ns: int) -> None:
        self._evict_stale(timestamp_ns)
        self._anomaly_timestamps.append(timestamp_ns)

    @property
    def sample_count(self) -> int:
        return len(self._samples)

    def mean_content_length(self) -> float:
        if not self._samples:
            return 0.0
        return sum(s[1] for s in self._samples) / len(self._samples)

    def request_rate(self, now_ns: int) -> float:
        """Requests per second over the baseline window."""
        self._evict_stale(now_ns)
        if self.window_seconds == 0:
            return 0.0
        return len(self._samples) / self.window_seconds

    def anomaly_pressure(self, now_ns: int) -> float:
        """Fraction of recent requests that were anomalous (0.0 – 1.0)."""
        self._evict_stale(now_ns)
        total = len(self._samples)
        if total == 0:
            return 0.0
        return min(1.0, len(self._anomaly_timestamps) / total)


class AdaptiveGuard:
    """Stateful, per-endpoint anomaly scorer.

    The anomaly score is a weighted combination of:
      - content-length deviation from the endpoint's rolling mean
      - request-rate deviation from the endpoint's rolling mean
      - current anomaly pressure (ratio of recent anomalies to total requests)

    The effective threshold shrinks under pressure so that a sustained attack
    is progressively harder to slip through.
    """

    def __init__(
        self,
        base_threshold: float = 0.85,
        baseline_window_s: float = 300.0,
        pressure_multiplier: float = 1.5,
        min_samples: int = 20,
        quarantine_ttl_s: float = 60.0,
    ) -> None:
        self._base_threshold = base_threshold
        self._window_s = baseline_window_s
        self._pressure_mult = pressure_multiplier
        self._min_samples = min_samples
        self._quarantine_ttl_ns = int(quarantine_ttl_s * 1e9)

        # (method, path_prefix) -> baseline
        self._baselines: dict[tuple[str, str], _EndpointBaseline] = {}
        # source_ip -> quarantine expiry timestamp_ns
        self._quarantine: dict[str, int] = {}

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def score(self, profile: RequestProfile) -> ThreatResult:
        """Score the request; return ThreatResult with anomaly score."""
        now_ns = profile.timestamp_ns

        # Check quarantine first — quarantined sources are rejected immediately.
        if self._is_quarantined(profile.source_ip, now_ns):
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.RATE_ANOMALY,
                reason=f"Source {profile.source_ip!r} is quarantined",
                profile=profile,
            )

        key = (profile.method, self._path_prefix(profile.path))
        baseline = self._baselines.setdefault(
            key,
            _EndpointBaseline(window_seconds=self._window_s, min_samples=self._min_samples),
        )

        # Not enough data yet → admit but record.
        if baseline.sample_count < self._min_samples:
            baseline.record(now_ns, profile.content_length)
            return ThreatResult(allowed=True, score=0.0, profile=profile)

        score = self._compute_score(profile, baseline, now_ns)
        effective_threshold = self._effective_threshold(baseline, now_ns)

        baseline.record(now_ns, profile.content_length)

        if score >= effective_threshold:
            baseline.record_anomaly(now_ns)
            self._quarantine[profile.source_ip] = now_ns + self._quarantine_ttl_ns
            return ThreatResult(
                allowed=False,
                score=score,
                vector=ThreatVector.PAYLOAD_ANOMALY,
                reason=(
                    f"Anomaly score {score:.3f} >= threshold {effective_threshold:.3f} "
                    f"for {profile.method} {profile.path!r}"
                ),
                profile=profile,
            )

        return ThreatResult(allowed=True, score=score, profile=profile)

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _path_prefix(path: str) -> str:
        """Normalise path to a two-segment prefix for baseline grouping.

        /api/v1/tool/scan/foo -> /api/v1
        """
        parts = [p for p in path.split("/") if p]
        return "/" + "/".join(parts[:2]) if parts else "/"

    def _is_quarantined(self, source_ip: str, now_ns: int) -> bool:
        expiry = self._quarantine.get(source_ip)
        if expiry is None:
            return False
        if now_ns > expiry:
            del self._quarantine[source_ip]
            return False
        return True

    def _compute_score(
        self,
        profile: RequestProfile,
        baseline: _EndpointBaseline,
        now_ns: int,
    ) -> float:
        """Weighted anomaly score in [0.0, 1.0]."""
        # -- content-length deviation (weight 0.5) --
        mean_cl = baseline.mean_content_length()
        if mean_cl > 0:
            cl_ratio = abs(profile.content_length - mean_cl) / mean_cl
            cl_score = min(1.0, cl_ratio / 5.0)   # normalise: 5× mean → score 1.0
        else:
            cl_score = 0.0

        # -- request-rate anomaly (weight 0.3) --
        rate = baseline.request_rate(now_ns)
        # score rises linearly: > 100 req/s on a normally-quiet endpoint → 1.0
        rate_score = min(1.0, rate / 100.0)

        # -- anomaly pressure (weight 0.2) --
        pressure = baseline.anomaly_pressure(now_ns)

        return 0.5 * cl_score + 0.3 * rate_score + 0.2 * pressure

    def _effective_threshold(self, baseline: _EndpointBaseline, now_ns: int) -> float:
        """Threshold tightens as anomaly pressure rises."""
        pressure = baseline.anomaly_pressure(now_ns)
        # Under zero pressure: base_threshold.
        # Under full pressure: base_threshold / pressure_multiplier.
        divisor = 1.0 + pressure * (self._pressure_mult - 1.0)
        return max(0.1, self._base_threshold / divisor)


# ---------------------------------------------------------------------------
# SecurityCore — Flask WSGI middleware
# ---------------------------------------------------------------------------


class SecurityCore:
    """Adaptive Immunity middleware.

    Wraps a Flask (or any WSGI) application.  Every request passes through
    the innate guard first, then the adaptive guard.

    Usage (Flask):
        app = Flask(__name__)
        app.wsgi_app = SecurityCore(app.wsgi_app, params_path=Path("params.json"))

    Security events are emitted to the provided *event_callback* (if any) so
    that the Signal Reactor can fan them out to downstream hooks.
    """

    def __init__(
        self,
        wsgi_app: Callable,  # type: ignore[type-arg]
        params_path: Path = _DEFAULT_PARAMS_PATH,
        event_callback: Callable[[str, ThreatResult], None] | None = None,
    ) -> None:
        params = _load_security_params(params_path)

        innate_cfg = params.get("innate", {})
        adaptive_cfg = params.get("adaptive", {})

        self._app = wsgi_app
        self._innate = InnateGuard(
            max_header_size=innate_cfg.get("max_header_size_bytes", 8192),
            max_path_depth=innate_cfg.get("max_path_depth", 10),
        )
        self._adaptive = AdaptiveGuard(
            base_threshold=params.get("anomaly_threshold", 0.85),
            baseline_window_s=float(adaptive_cfg.get("baseline_window_seconds", 300)),
            pressure_multiplier=float(adaptive_cfg.get("pressure_multiplier", 1.5)),
            min_samples=int(adaptive_cfg.get("min_samples_for_baseline", 20)),
            quarantine_ttl_s=float(adaptive_cfg.get("quarantine_ttl_seconds", 60)),
        )
        self._callback = event_callback

    def __call__(self, environ: dict, start_response: Callable) -> object:  # type: ignore[type-arg]
        profile = self._build_profile(environ)
        msgid = time.time_ns()

        # --- innate check ---
        innate_result = self._innate.check(profile)
        if not innate_result.allowed:
            self._log_block(msgid, innate_result)
            self._notify(innate_result)
            return self._respond(start_response, 403, innate_result.reason)

        # --- adaptive check ---
        adaptive_result = self._adaptive.score(profile)
        if not adaptive_result.allowed:
            self._log_block(msgid, adaptive_result)
            self._notify(adaptive_result)
            return self._respond(start_response, 429, adaptive_result.reason)

        # Log clean pass at DEBUG so forensics always has a full audit trail.
        logger.debug(
            "[msgid:%d] SecurityCore: PASS score=%.3f src=%s path=%s",
            msgid,
            adaptive_result.score,
            profile.source_ip,
            profile.path,
        )
        return self._app(environ, start_response)

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _build_profile(environ: dict) -> RequestProfile:  # type: ignore[type-arg]
        """Extract a RequestProfile from the WSGI environ."""
        path = environ.get("PATH_INFO", "/")
        path_depth = len([p for p in path.split("/") if p])
        content_length = int(environ.get("CONTENT_LENGTH") or 0)
        header_size = sum(
            len(k) + len(str(v)) + 4   # "Key: Value\r\n"
            for k, v in environ.items()
            if k.startswith("HTTP_")
        )
        return RequestProfile(
            source_ip=environ.get("HTTP_X_FORWARDED_FOR", environ.get("REMOTE_ADDR", "unknown")),
            method=environ.get("REQUEST_METHOD", "GET"),
            path=path,
            path_depth=path_depth,
            content_length=content_length,
            header_size=header_size,
            engagement_id=environ.get("HTTP_X_ENGAGEMENT_ID", ""),
        )

    @staticmethod
    def _respond(
        start_response: Callable,  # type: ignore[type-arg]
        status_code: int,
        reason: str,
    ) -> list[bytes]:
        status_map = {403: "403 Forbidden", 429: "429 Too Many Requests"}
        status = status_map.get(status_code, f"{status_code} Error")
        body = json.dumps({"error": reason}).encode()
        start_response(
            status,
            [("Content-Type", "application/json"), ("Content-Length", str(len(body)))],
        )
        return [body]

    def _notify(self, result: ThreatResult) -> None:
        if self._callback is not None:
            try:
                self._callback("security.threat", result)
            except Exception:
                logger.exception("[msgid:%d] SecurityCore: event_callback raised", time.time_ns())

    @staticmethod
    def _log_block(msgid: int, result: ThreatResult) -> None:
        profile = result.profile
        src = profile.source_ip if profile else "unknown"
        path = profile.path if profile else "unknown"
        eng = profile.engagement_id if profile else ""
        logger.warning(
            "[msgid:%d] SecurityCore: BLOCK vector=%s score=%.3f src=%s path=%s engagement=%s reason=%s",
            msgid,
            result.vector.name,
            result.score,
            src,
            path,
            eng,
            result.reason,
        )
