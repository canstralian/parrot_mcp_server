"""Pydantic v2 domain models for the multi-agent orchestration framework.

These are the canonical data contracts passed between all layers (queue,
database, orchestrator, MCP tools).  No database or Redis coupling here.
"""
from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


def _utcnow() -> datetime:
    return datetime.now(tz=timezone.utc)


class AgentCapability(BaseModel):
    """A single skill advertised by a registered agent."""

    model_config = ConfigDict(frozen=False)

    name: str
    description: str
    # JSON-schema-style parameter spec so callers know what payload to send
    parameters: dict[str, Any] = Field(default_factory=dict)


class AgentRegistration(BaseModel):
    """What an agent submits when it joins the orchestration pool."""

    model_config = ConfigDict(frozen=False)

    agent_id: str
    name: str
    capabilities: list[AgentCapability]
    # Optional callback URL for push-style result delivery
    endpoint: str | None = None
    registered_at: datetime = Field(default_factory=_utcnow)
    last_heartbeat: datetime = Field(default_factory=_utcnow)
    healthy: bool = True


class TaskStatus(str, Enum):
    PENDING = "pending"
    ASSIGNED = "assigned"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class Task(BaseModel):
    """A unit of work dispatched to an agent."""

    model_config = ConfigDict(frozen=False)

    task_id: str
    # Ties back to the auth.py Engagement — all tool calls require this
    engagement_id: str
    # The AgentCapability.name that must be available on the assigned agent
    capability_required: str
    # Scope-checked against the engagement before dispatch
    target: str
    payload: dict[str, Any] = Field(default_factory=dict)
    status: TaskStatus = TaskStatus.PENDING
    assigned_agent_id: str | None = None
    result: dict[str, Any] | None = None
    error: str | None = None
    created_at: datetime = Field(default_factory=_utcnow)
    updated_at: datetime = Field(default_factory=_utcnow)


class Workflow(BaseModel):
    """An ordered sequence of tasks executed as a unit."""

    model_config = ConfigDict(frozen=False)

    workflow_id: str
    engagement_id: str
    name: str
    # Ordered list of task_ids; tasks are submitted individually
    task_ids: list[str]
    status: TaskStatus = TaskStatus.PENDING
    created_at: datetime = Field(default_factory=_utcnow)


class OrchestratorStatus(BaseModel):
    """Snapshot returned by the status tool — no auth required."""

    model_config = ConfigDict(frozen=False)

    agent_count: int
    healthy_agents: int
    pending_tasks: int
    running_tasks: int
    queue_depth: int
