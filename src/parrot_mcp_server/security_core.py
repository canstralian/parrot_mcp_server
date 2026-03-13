"""Security Core — adaptive immunity middleware for the Parrot MCP Server.

Two-layer threat detection modelled after biological immunity:

* **Innate layer** (InnateGuard) — stateless, compiled-regex pattern matching.
  Blocks injection, XSS, and path-traversal patterns immediately, before any
  business logic runs.

* **Adaptive layer** (AdaptiveGuard) — per-endpoint baseline learning with
  anomaly scoring.  Thresholds tighten automatically under sustained pressure
  and suspicious sources are quarantined with TTL expiry.

SecurityCore wires both layers together as WSGI middleware and emits security
events via an optional async callback so the SignalReactor can fan them out.
"""

from __future__ import annotations

import json
import logging
import re
import time
from collections import deque
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Any, Callable, Coroutine

try:
    from pydantic import BaseModel
except ImportError:  # graceful degradation when pydantic not installed
    BaseModel = object  # type: ignore[assignment, misc]

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Load runtime-tunable parameters
# ---------------------------------------------------------------------------

_PARAMS_PATH = Path(__file__).parent.parent.parent / "params.json"
_DEFAULT_PARAMS: dict[str, Any] = {
    "signal_reactor": {"timeout_ms": 500, "max_concurrency": 20},
    "security": {
        "max_header_bytes": 8192,
        "max_path_depth": 10,
        "rate_window_s": 60,
        "rate_anomaly_multiplier": 3.0,
        "quarantine_ttl_s": 300,
        "adaptive_pressure_decay": 0.9,
        "anomaly_score_threshold": 0.75,
    },
    "plugin_isolation_level": "strict",
}

try:
    _PARAMS: dict[str, Any] = json.loads(_PARAMS_PATH.read_text()) if _PARAMS_PATH.exists() else _DEFAULT_PARAMS
except (json.JSONDecodeError, OSError):
    _PARAMS = _DEFAULT_PARAMS

_SEC = _PARAMS.get("security", _DEFAULT_PARAMS["security"])


# ---------------------------------------------------------------------------
# Domain models
# ---------------------------------------------------------------------------


class ThreatVector(Enum):
    """Categorises detected threats for structured logging and metrics."""

    NONE = "none"
    PATH_TRAVERSAL = "path_traversal"
    INJECTION = "injection"
    XSS = "xss"
    OVERSIZED_HEADER = "oversized_header"
    EXCESSIVE_DEPTH = "excessive_depth"
    RATE_ANOMALY = "rate_anomaly"
    PAYLOAD_ANOMALY = "payload_anomaly"


class RequestProfile(BaseModel):
    """Snapshot of inbound request characteristics for scoring."""

    source_ip: str
    method: str
    path: str
    path_depth: int
    content_length: int
    header_size: int
    engagement_id: str
    timestamp_ns: int


@dataclass
class ThreatResult:
    """Outcome of a security check."""

    allowed: bool
    score: float  # 0.0 = clean, 1.0 = certain threat
    vector: ThreatVector
    reason: str
    profile: RequestProfile | None = None

    @property
    def http_status(self) -> int:
        if self.allowed:
            return 200
        if self.vector == ThreatVector.RATE_ANOMALY:
            return 429
        return 403


# ---------------------------------------------------------------------------
# Innate Guard — stateless pattern matching
# ---------------------------------------------------------------------------

_INJECTION_RE = re.compile(
    r"(union\s+select|drop\s+table|insert\s+into|exec\s*\(|xp_cmdshell)",
    re.IGNORECASE,
)
_XSS_RE = re.compile(
    r"(<\s*script|javascript\s*:|on\w+\s*=|<\s*iframe|<\s*object)",
    re.IGNORECASE,
)
_PATH_TRAVERSAL_RE = re.compile(r"(\.\./|\.\.\\|%2e%2e)", re.IGNORECASE)
_SENSITIVE_PATH_RE = re.compile(
    r"(/etc/passwd|/proc/|/sys/|\.env$|/\.git/|/\.ssh/)",
    re.IGNORECASE,
)


class InnateGuard:
    """Stateless, fast pattern-matching layer.

    All checks are O(n) in request size with no shared mutable state so this
    layer is safe to use from multiple coroutines without locking.
    """

    def __init__(
        self,
        max_header_bytes: int = _SEC["max_header_bytes"],
        max_path_depth: int = _SEC["max_path_depth"],
    ) -> None:
        self._max_header_bytes = max_header_bytes
        self._max_path_depth = max_path_depth

    def check(self, profile: RequestProfile) -> ThreatResult:
        """Run all innate checks; return on first violation (fail-fast)."""

        if profile.header_size > self._max_header_bytes:
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.OVERSIZED_HEADER,
                reason=f"Header size {profile.header_size}B exceeds limit {self._max_header_bytes}B",
                profile=profile,
            )

        if profile.path_depth > self._max_path_depth:
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.EXCESSIVE_DEPTH,
                reason=f"Path depth {profile.path_depth} exceeds limit {self._max_path_depth}",
                profile=profile,
            )

        if _PATH_TRAVERSAL_RE.search(profile.path) or _SENSITIVE_PATH_RE.search(profile.path):
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.PATH_TRAVERSAL,
                reason=f"Path traversal / sensitive path detected: {profile.path!r}",
                profile=profile,
            )

        if _INJECTION_RE.search(profile.path):
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.INJECTION,
                reason="SQL/command injection pattern detected in path",
                profile=profile,
            )

        if _XSS_RE.search(profile.path):
            return ThreatResult(
                allowed=False,
                score=1.0,
                vector=ThreatVector.XSS,
                reason="XSS pattern detected in path",
                profile=profile,
            )

        return ThreatResult(allowed=True, score=0.0, vector=ThreatVector.NONE, reason="clean", profile=profile)


# ---------------------------------------------------------------------------
# Adaptive Guard — per-endpoint baseline + anomaly scoring
# ---------------------------------------------------------------------------

@dataclass
class _EndpointStats:
    """Rolling statistics for a single (method, path_prefix) pair."""

    content_lengths: deque[int] = field(default_factory=lambda: deque(maxlen=200))
    request_times_ns: deque[int] = field(default_factory=lambda: deque(maxlen=500))
    anomaly_pressure: float = 0.0  # accumulated pressure; decays over time


@dataclass
class _Quarantine:
    expires_ns: int


class AdaptiveGuard:
    """Per-endpoint baseline learning with anomaly scoring.

    The guard maintains rolling statistics per ``(method, path_prefix)`` key.
    Anomaly pressure accumulates when violations occur and decays between
    requests, allowing the guard to self-heal after attacks subside.
    """

    def __init__(
        self,
        rate_window_s: float = _SEC["rate_window_s"],
        rate_anomaly_multiplier: float = _SEC["rate_anomaly_multiplier"],
        quarantine_ttl_s: float = _SEC["quarantine_ttl_s"],
        pressure_decay: float = _SEC["adaptive_pressure_decay"],
        score_threshold: float = _SEC["anomaly_score_threshold"],
    ) -> None:
        self._stats: dict[str, _EndpointStats] = {}
        self._quarantine: dict[str, _Quarantine] = {}
        self._rate_window_ns = int(rate_window_s * 1e9)
        self._rate_multiplier = rate_anomaly_multiplier
        self._quarantine_ttl_ns = int(quarantine_ttl_s * 1e9)
        self._pressure_decay = pressure_decay
        self._score_threshold = score_threshold

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def check(self, profile: RequestProfile) -> ThreatResult:
        """Score the request; quarantine source if threshold exceeded."""
        now_ns = profile.timestamp_ns

        # Check existing quarantine first.
        q = self._quarantine.get(profile.source_ip)
        if q:
            if now_ns < q.expires_ns:
                return ThreatResult(
                    allowed=False,
                    score=1.0,
                    vector=ThreatVector.RATE_ANOMALY,
                    reason=f"Source {profile.source_ip} is quarantined",
                    profile=profile,
                )
            # TTL expired — lift quarantine.
            del self._quarantine[profile.source_ip]

        key = self._endpoint_key(profile)
        stats = self._stats.setdefault(key, _EndpointStats())

        score = self._score(profile, stats, now_ns)
        self._update(profile, stats, now_ns)

        # Apply pressure decay.
        stats.anomaly_pressure = min(1.0, stats.anomaly_pressure * self._pressure_decay + score * self._pressure_gain)

        # Threshold tightens under sustained pressure.
        effective_threshold = self._score_threshold * (1.0 - stats.anomaly_pressure * self._threshold_sensitivity)


        if score >= effective_threshold:
            self._quarantine[profile.source_ip] = _Quarantine(
                expires_ns=now_ns + self._quarantine_ttl_ns
            )
            logger.warning(
                "[msgid:%d] AdaptiveGuard: quarantining %s score=%.3f vector=payload_anomaly",
                now_ns,
                profile.source_ip,
                score,
            )
            return ThreatResult(
                allowed=False,
                score=score,
                vector=ThreatVector.PAYLOAD_ANOMALY,
                reason=f"Anomaly score {score:.3f} >= threshold {effective_threshold:.3f}",
                profile=profile,
            )

        return ThreatResult(allowed=True, score=score, vector=ThreatVector.NONE, reason="within baseline", profile=profile)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _endpoint_key(profile: RequestProfile) -> str:
        # Group by method + first two path segments to avoid cardinality explosion.
        parts = profile.path.split("/")[:3]
        return f"{profile.method}:{'/'.join(parts)}"

    def _score(self, profile: RequestProfile, stats: _EndpointStats, now_ns: int) -> float:
        scores: list[float] = []

        # Content-length deviation.
        if len(stats.content_lengths) >= 10:
            mean_cl = sum(stats.content_lengths) / len(stats.content_lengths)
            if mean_cl > 0:
                deviation = abs(profile.content_length - mean_cl) / mean_cl
                scores.append(min(1.0, deviation / 5.0))

        # Request-rate deviation.
        cutoff = now_ns - self._rate_window_ns
        recent = sum(1 for t in stats.request_times_ns if t >= cutoff)
        if recent > 0 and len(stats.request_times_ns) >= 10:
            window_s = self._rate_window_ns / 1e9
            avg_rate = len(stats.request_times_ns) / window_s
            current_rate = recent / window_s
            if avg_rate > 0 and current_rate > avg_rate * self._rate_multiplier:
                scores.append(min(1.0, (current_rate / avg_rate) / self._rate_multiplier))

        return max(scores) if scores else 0.0

    @staticmethod
    def _update(profile: RequestProfile, stats: _EndpointStats, now_ns: int) -> None:
        stats.content_lengths.append(profile.content_length)
        stats.request_times_ns.append(now_ns)


# ---------------------------------------------------------------------------
# SecurityCore — WSGI middleware wiring both layers
# ---------------------------------------------------------------------------

EventCallback = Callable[[ThreatResult], Coroutine[Any, Any, None]]


class SecurityCore:
    """WSGI middleware that chains InnateGuard → AdaptiveGuard.

    Wrap a Flask (or any WSGI) application::

        app.wsgi_app = SecurityCore(app.wsgi_app, on_event=reactor.emit_security)

    *on_event* is an optional async callback; it is scheduled as a fire-and-forget
    task so it never blocks the synchronous WSGI path.
    """

    def __init__(
        self,
        app: Any,
        on_event: EventCallback | None = None,
        innate: InnateGuard | None = None,
        adaptive: AdaptiveGuard | None = None,
    ) -> None:
        self._app = app
        self._on_event = on_event
        self._innate = innate or InnateGuard()
        self._adaptive = adaptive or AdaptiveGuard()

    # ------------------------------------------------------------------
    # WSGI interface
    # ------------------------------------------------------------------

    def __call__(self, environ: dict[str, Any], start_response: Any) -> Any:
        profile = self._build_profile(environ)

        # Innate check first (stateless, fast).
        result = self._innate.check(profile)
        if not result.allowed:
            return self._reject(result, start_response)

        # Adaptive check second (stateful, learning).
        result = self._adaptive.check(profile)
        if not result.allowed:
            return self._reject(result, start_response)

        return self._app(environ, start_response)

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _build_profile(environ: dict[str, Any]) -> RequestProfile:
        path = environ.get("PATH_INFO", "/")
        header_size = sum(
            len(k) + len(str(v)) + 4
            for k, v in environ.items()
            if k.startswith("HTTP_")
        )
        return RequestProfile(
            source_ip=environ.get("REMOTE_ADDR", "0.0.0.0"),
            method=environ.get("REQUEST_METHOD", "GET"),
            path=path,
            path_depth=len([p for p in path.split("/") if p]),
            content_length=int(environ.get("CONTENT_LENGTH") or 0),
            header_size=header_size,
            engagement_id=environ.get("HTTP_X_ENGAGEMENT_ID", ""),
            timestamp_ns=time.time_ns(),
        )

    def _reject(self, result: ThreatResult, start_response: Any) -> list[bytes]:
        msgid = time.time_ns()
        logger.warning(
            "[msgid:%d] SecurityCore: blocked %s score=%.3f reason=%s",
            msgid,
            result.vector.value,
            result.score,
            result.reason,
        )
        self._fire_event(result)
        status = f"{result.http_status} {'Forbidden' if result.http_status == 403 else 'Too Many Requests'}"
        body = json.dumps({"error": result.reason, "vector": result.vector.value}).encode()
        start_response(status, [("Content-Type", "application/json"), ("Content-Length", str(len(body)))])
        return [body]

    def _fire_event(self, result: ThreatResult) -> None:
        """Schedule the async event callback without blocking the WSGI path."""
        if self._on_event is None:
            return
        import asyncio  # noqa: PLC0415

        try:
            loop = asyncio.get_running_loop()
            loop.create_task(self._on_event(result))
        except RuntimeError:
            # No running loop in synchronous context — skip event.
            pass
