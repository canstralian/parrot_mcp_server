"""Task queue for the multi-agent orchestration framework.

Primary backend: Redis (PARROT_REDIS_URL, default redis://localhost:6379/0).
Fallback backend: in-process SimpleQueue when PARROT_QUEUE_BACKEND=memory.

The in-memory backend is single-process only and is provided for
development / CI environments that don't have Redis.

Redis key layout:
    parrot:tasks:pending          LIST  — FIFO queue of task_id strings
    parrot:tasks:{task_id}        HASH  — full task JSON payload
    parrot:agents:heartbeats      ZSET  — agent_id → last heartbeat epoch
"""
from __future__ import annotations

import json
import os
import queue as _stdlib_queue
import time
from typing import Any

from parrot_mcp_server.models import Task

# ---------------------------------------------------------------------------
# Redis-backed queue
# ---------------------------------------------------------------------------

_PENDING_KEY = "parrot:tasks:pending"
_TASK_KEY_PREFIX = "parrot:tasks:"
_HEARTBEAT_KEY = "parrot:agents:heartbeats"


class RedisTaskQueue:
    """Redis-backed FIFO task queue."""

    def __init__(self, redis_url: str) -> None:
        try:
            from redis import Redis  # type: ignore[import-untyped]
        except ImportError as exc:
            raise ImportError(
                "redis package is required for RedisTaskQueue. "
                "Install it with: pip install 'parrot-mcp-server[full]'"
            ) from exc

        self._r = Redis.from_url(redis_url, decode_responses=True)

    def enqueue(self, task: Task) -> None:
        """Store task payload and push task_id onto the pending list atomically."""
        task_json = task.model_dump_json()
        pipe = self._r.pipeline()
        pipe.hset(_TASK_KEY_PREFIX + task.task_id, "data", task_json)
        pipe.rpush(_PENDING_KEY, task.task_id)
        pipe.execute()

    def dequeue(self, timeout: int = 1) -> Task | None:
        """Pop the next task_id from the queue and return the full Task.

        Returns None if the queue is empty (after *timeout* seconds).
        """
        result = self._r.blpop(_PENDING_KEY, timeout=timeout)
        if result is None:
            return None
        _, task_id = result
        task_json = self._r.hget(_TASK_KEY_PREFIX + task_id, "data")
        if task_json is None:
            return None
        return Task.model_validate_json(task_json)

    def update_task(self, task: Task) -> None:
        """Overwrite the stored task payload (status / result updates)."""
        self._r.hset(_TASK_KEY_PREFIX + task.task_id, "data", task.model_dump_json())

    def depth(self) -> int:
        """Return the number of tasks waiting in the pending queue."""
        return self._r.llen(_PENDING_KEY)

    def record_heartbeat(self, agent_id: str) -> None:
        """Update the agent's heartbeat timestamp in the sorted set."""
        self._r.zadd(_HEARTBEAT_KEY, {agent_id: time.time()})

    def stale_agents(self, max_age_seconds: int = 30) -> list[str]:
        """Return agent IDs whose last heartbeat is older than *max_age_seconds*."""
        cutoff = time.time() - max_age_seconds
        # ZRANGEBYSCORE returns members with score between -inf and cutoff
        return self._r.zrangebyscore(_HEARTBEAT_KEY, "-inf", cutoff)

    def remove_agent_heartbeat(self, agent_id: str) -> None:
        """Remove an agent from the heartbeat sorted set."""
        self._r.zrem(_HEARTBEAT_KEY, agent_id)


# ---------------------------------------------------------------------------
# In-memory fallback queue (single-process, for dev / CI without Redis)
# ---------------------------------------------------------------------------


class MemoryTaskQueue:
    """Simple in-process queue backed by stdlib queue.SimpleQueue.

    WARNING: Not suitable for multi-process deployments.  This backend
    exists solely for development and testing environments that do not
    have Redis available.
    """

    def __init__(self) -> None:
        self._q: _stdlib_queue.SimpleQueue[Task] = _stdlib_queue.SimpleQueue()
        self._store: dict[str, Task] = {}
        self._heartbeats: dict[str, float] = {}

    def enqueue(self, task: Task) -> None:
        self._store[task.task_id] = task
        self._q.put(task)

    def dequeue(self, timeout: int = 1) -> Task | None:
        try:
            return self._q.get_nowait()
        except _stdlib_queue.Empty:
            return None

    def update_task(self, task: Task) -> None:
        self._store[task.task_id] = task

    def depth(self) -> int:
        return self._q.qsize()

    def record_heartbeat(self, agent_id: str) -> None:
        self._heartbeats[agent_id] = time.time()

    def stale_agents(self, max_age_seconds: int = 30) -> list[str]:
        cutoff = time.time() - max_age_seconds
        return [aid for aid, ts in self._heartbeats.items() if ts < cutoff]

    def remove_agent_heartbeat(self, agent_id: str) -> None:
        self._heartbeats.pop(agent_id, None)


# ---------------------------------------------------------------------------
# Unified public type / factory
# ---------------------------------------------------------------------------

# Union type that callers can annotate with
TaskQueue = RedisTaskQueue | MemoryTaskQueue


def create_queue(
    redis_url: str | None = None,
    backend: str | None = None,
) -> TaskQueue:
    """Return the appropriate queue backend.

    Selection order:
    1. *backend* argument (if provided)
    2. PARROT_QUEUE_BACKEND env var
    3. 'redis' if PARROT_REDIS_URL or default redis:// is reachable
    4. Falls back to 'memory' with a warning

    Args:
        redis_url: Override for PARROT_REDIS_URL.
        backend:   Force 'redis' or 'memory'.
    """
    resolved_backend = backend or os.getenv("PARROT_QUEUE_BACKEND", "redis")

    if resolved_backend == "memory":
        return MemoryTaskQueue()

    url = redis_url or os.getenv("PARROT_REDIS_URL", "redis://localhost:6379/0")
    return RedisTaskQueue(url)
