"""SQLAlchemy database layer for the orchestration framework.

Supports PostgreSQL (production) and SQLite (development/test).
Set PARROT_DB_URL to override the default SQLite path.

Example:
    PARROT_DB_URL=postgresql+psycopg2://user:pass@localhost/parrot  # production
    PARROT_DB_URL=sqlite:///./parrot_mcp.db                          # default dev
    PARROT_DB_URL=sqlite:///:memory:                                  # tests
"""
from __future__ import annotations

import json
import os
from contextlib import contextmanager
from datetime import datetime, timezone
from typing import Any, Iterator

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    String,
    Text,
    create_engine,
)
from sqlalchemy.orm import DeclarativeBase, Session

from parrot_mcp_server.models import (
    AgentCapability,
    AgentRegistration,
    Task,
    TaskStatus,
    Workflow,
)

# ---------------------------------------------------------------------------
# Module-level engine (initialised by init_db)
# ---------------------------------------------------------------------------

_ENGINE = None


def init_db(database_url: str | None = None) -> Any:
    """Initialise the database engine and create tables if they don't exist.

    Returns the engine so callers can inspect it in tests.
    """
    global _ENGINE
    url = database_url or os.getenv(
        "PARROT_DB_URL", "sqlite:///./parrot_mcp.db"
    )
    # check_same_thread=False is required for SQLite when used with
    # asyncio.to_thread — harmless for Postgres.
    connect_args: dict[str, Any] = {}
    if url.startswith("sqlite"):
        connect_args["check_same_thread"] = False

    _ENGINE = create_engine(url, echo=False, future=True, connect_args=connect_args)
    Base.metadata.create_all(_ENGINE)
    return _ENGINE


@contextmanager
def get_session() -> Iterator[Session]:
    """Yield a SQLAlchemy session, committing on exit or rolling back on error."""
    if _ENGINE is None:
        raise RuntimeError("Database not initialised — call init_db() first")
    with Session(_ENGINE) as session:
        try:
            yield session
            session.commit()
        except Exception:
            session.rollback()
            raise


# ---------------------------------------------------------------------------
# ORM models
# ---------------------------------------------------------------------------


class Base(DeclarativeBase):
    pass


class AgentRow(Base):
    __tablename__ = "agents"

    agent_id = Column(String, primary_key=True)
    name = Column(String, nullable=False)
    # Stored as JSON text
    capabilities = Column(Text, nullable=False, default="[]")
    endpoint = Column(String, nullable=True)
    healthy = Column(Boolean, nullable=False, default=True)
    last_heartbeat = Column(DateTime(timezone=True), nullable=False)
    registered_at = Column(DateTime(timezone=True), nullable=False)


class TaskRow(Base):
    __tablename__ = "tasks"

    task_id = Column(String, primary_key=True)
    # engagement_id is not an FK — engagements live in-memory in auth.py
    engagement_id = Column(String, nullable=False)
    capability_required = Column(String, nullable=False)
    target = Column(String, nullable=False)
    payload = Column(Text, nullable=False, default="{}")
    status = Column(String, nullable=False, default="pending")
    assigned_agent_id = Column(String, nullable=True)
    result = Column(Text, nullable=True)
    error = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), nullable=False)
    updated_at = Column(DateTime(timezone=True), nullable=False)


class WorkflowRow(Base):
    __tablename__ = "workflows"

    workflow_id = Column(String, primary_key=True)
    engagement_id = Column(String, nullable=False)
    name = Column(String, nullable=False)
    # Ordered list of task_id strings stored as JSON
    task_ids = Column(Text, nullable=False, default="[]")
    status = Column(String, nullable=False, default="pending")
    created_at = Column(DateTime(timezone=True), nullable=False)


# ---------------------------------------------------------------------------
# Mapper helpers — isolate ORM types from orchestrator code
# ---------------------------------------------------------------------------


def agent_to_model(row: AgentRow) -> AgentRegistration:
    caps_raw: list[dict[str, Any]] = json.loads(row.capabilities or "[]")
    caps = [AgentCapability(**c) for c in caps_raw]
    return AgentRegistration(
        agent_id=row.agent_id,
        name=row.name,
        capabilities=caps,
        endpoint=row.endpoint,
        registered_at=_ensure_tz(row.registered_at),
        last_heartbeat=_ensure_tz(row.last_heartbeat),
        healthy=bool(row.healthy),
    )


def task_to_model(row: TaskRow) -> Task:
    payload: dict[str, Any] = json.loads(row.payload or "{}")
    result: dict[str, Any] | None = json.loads(row.result) if row.result else None
    return Task(
        task_id=row.task_id,
        engagement_id=row.engagement_id,
        capability_required=row.capability_required,
        target=row.target,
        payload=payload,
        status=TaskStatus(row.status),
        assigned_agent_id=row.assigned_agent_id,
        result=result,
        error=row.error,
        created_at=_ensure_tz(row.created_at),
        updated_at=_ensure_tz(row.updated_at),
    )


def model_to_task_row(task: Task) -> TaskRow:
    return TaskRow(
        task_id=task.task_id,
        engagement_id=task.engagement_id,
        capability_required=task.capability_required,
        target=task.target,
        payload=json.dumps(task.payload),
        status=task.status.value,
        assigned_agent_id=task.assigned_agent_id,
        result=json.dumps(task.result) if task.result is not None else None,
        error=task.error,
        created_at=task.created_at,
        updated_at=task.updated_at,
    )


def model_to_agent_row(reg: AgentRegistration) -> AgentRow:
    caps = [c.model_dump() for c in reg.capabilities]
    return AgentRow(
        agent_id=reg.agent_id,
        name=reg.name,
        capabilities=json.dumps(caps),
        endpoint=reg.endpoint,
        healthy=reg.healthy,
        last_heartbeat=reg.last_heartbeat,
        registered_at=reg.registered_at,
    )


def _ensure_tz(dt: datetime | None) -> datetime:
    """Return datetime with UTC timezone (SQLite strips tzinfo on round-trip)."""
    if dt is None:
        return datetime.now(tz=timezone.utc)
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt


# ---------------------------------------------------------------------------
# DB helper queries used by the orchestrator
# ---------------------------------------------------------------------------


def persist_task(task: Task) -> None:
    with get_session() as session:
        existing = session.get(TaskRow, task.task_id)
        if existing:
            existing.status = task.status.value
            existing.assigned_agent_id = task.assigned_agent_id
            existing.result = json.dumps(task.result) if task.result is not None else None
            existing.error = task.error
            existing.updated_at = task.updated_at
        else:
            session.add(model_to_task_row(task))


def persist_agent(reg: AgentRegistration) -> None:
    caps = [c.model_dump() for c in reg.capabilities]
    with get_session() as session:
        existing = session.get(AgentRow, reg.agent_id)
        if existing:
            existing.name = reg.name
            existing.capabilities = json.dumps(caps)
            existing.endpoint = reg.endpoint
            existing.healthy = reg.healthy
            existing.last_heartbeat = reg.last_heartbeat
        else:
            session.add(model_to_agent_row(reg))


def persist_workflow(workflow: Workflow) -> None:
    with get_session() as session:
        existing = session.get(WorkflowRow, workflow.workflow_id)
        if existing:
            existing.status = workflow.status.value
            existing.task_ids = json.dumps(workflow.task_ids)
        else:
            session.add(
                WorkflowRow(
                    workflow_id=workflow.workflow_id,
                    engagement_id=workflow.engagement_id,
                    name=workflow.name,
                    task_ids=json.dumps(workflow.task_ids),
                    status=workflow.status.value,
                    created_at=workflow.created_at,
                )
            )


def load_healthy_agents() -> list[AgentRegistration]:
    """Load all healthy agents from DB — used to repopulate registry on startup."""
    with get_session() as session:
        rows = session.query(AgentRow).filter(AgentRow.healthy.is_(True)).all()
        return [agent_to_model(r) for r in rows]


def count_tasks_by_status(status: TaskStatus) -> int:
    with get_session() as session:
        return session.query(TaskRow).filter(TaskRow.status == status.value).count()
