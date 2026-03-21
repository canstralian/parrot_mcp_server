"""Unit tests for the multi-agent orchestration framework.

Uses SQLite in-memory for DB and the MemoryTaskQueue backend so no external
services (Redis, Postgres) are required.  Run with:

    pytest tests/test_orchestrator.py -v
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from parrot_mcp_server.auth import Engagement, register_engagement
from parrot_mcp_server.db import init_db
from parrot_mcp_server.models import (
    AgentCapability,
    AgentRegistration,
    Task,
    TaskStatus,
    Workflow,
)
from parrot_mcp_server.orchestrator import Orchestrator, make_task_id, make_workflow_id
from parrot_mcp_server.queue import MemoryTaskQueue


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def in_memory_db():
    """Initialise a fresh SQLite in-memory DB for every test."""
    init_db("sqlite:///:memory:")


@pytest.fixture()
def queue() -> MemoryTaskQueue:
    return MemoryTaskQueue()


@pytest.fixture()
def orch(queue: MemoryTaskQueue) -> Orchestrator:
    return Orchestrator(queue)


@pytest.fixture()
def active_engagement() -> str:
    """Register and return an engagement ID valid for the next hour."""
    now = datetime.now(tz=timezone.utc)
    eng = Engagement(
        engagement_id=f"eng-{uuid.uuid4().hex[:8]}",
        scope=["192.168.1.", "10.0.0.", "*"],
        authorized_by="test-officer@example.com",
        start_utc=now - timedelta(minutes=1),
        end_utc=now + timedelta(hours=1),
        rules_of_engagement="Test engagement — all targets in scope",
        teams=["red"],
    )
    return register_engagement(eng)


@pytest.fixture()
def expired_engagement() -> str:
    """Register and return an engagement that has already expired."""
    past = datetime.now(tz=timezone.utc) - timedelta(hours=2)
    eng = Engagement(
        engagement_id=f"eng-expired-{uuid.uuid4().hex[:8]}",
        scope=["*"],
        authorized_by="test-officer@example.com",
        start_utc=past - timedelta(hours=1),
        end_utc=past,
        rules_of_engagement="Expired engagement",
        teams=["red"],
    )
    return register_engagement(eng)


def _make_agent(name: str = "scanner", capability: str = "port_scan") -> AgentRegistration:
    return AgentRegistration(
        agent_id=f"agent-{uuid.uuid4().hex[:8]}",
        name=name,
        capabilities=[
            AgentCapability(
                name=capability,
                description=f"Performs {capability}",
                parameters={"target": {"type": "string"}},
            )
        ],
    )


def _make_task(
    engagement_id: str,
    capability: str = "port_scan",
    target: str = "192.168.1.100",
) -> Task:
    return Task(
        task_id=make_task_id(),
        engagement_id=engagement_id,
        capability_required=capability,
        target=target,
        payload={"ports": "1-1024"},
    )


# ---------------------------------------------------------------------------
# Auth gate enforcement
# ---------------------------------------------------------------------------


class TestAuthGate:
    def test_register_agent_fails_expired_engagement(
        self, orch: Orchestrator, expired_engagement: str
    ) -> None:
        reg = _make_agent()
        with pytest.raises(PermissionError, match="outside its authorized window"):
            orch.register_agent(expired_engagement, reg)

    def test_register_agent_fails_unknown_engagement(self, orch: Orchestrator) -> None:
        reg = _make_agent()
        with pytest.raises(PermissionError, match="No active engagement"):
            orch.register_agent("nonexistent-engagement", reg)

    def test_submit_task_fails_out_of_scope_target(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        # active_engagement scope includes 192.168.1.*, 10.0.0.*, *
        # But the scope list in auth.py checks prefix matching — "172.16" not in scope
        # Note: scope includes "*" wildcard so every target matches in this fixture.
        # Re-create engagement with a restricted scope to test rejection.
        from parrot_mcp_server.auth import _ACTIVE_ENGAGEMENTS

        # Temporarily patch scope to test rejection
        eng = _ACTIVE_ENGAGEMENTS[active_engagement]
        original_scope = eng.scope
        eng.scope = ["192.168.1."]
        try:
            task = _make_task(active_engagement, target="172.16.0.1")
            with pytest.raises(PermissionError, match="NOT in scope"):
                orch.submit_task(active_engagement, task)
        finally:
            eng.scope = original_scope

    def test_complete_task_fails_expired_engagement(
        self,
        orch: Orchestrator,
        active_engagement: str,
        expired_engagement: str,
    ) -> None:
        # Submit under valid engagement
        agent = _make_agent()
        orch.register_agent(active_engagement, agent)
        task = _make_task(active_engagement)
        task_id = orch.submit_task(active_engagement, task)

        # Try to complete under expired engagement
        with pytest.raises(PermissionError):
            orch.complete_task(expired_engagement, task_id, result={"open_ports": []})


# ---------------------------------------------------------------------------
# Agent registration
# ---------------------------------------------------------------------------


class TestAgentRegistration:
    def test_register_agent_appears_in_status(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        reg = _make_agent()
        orch.register_agent(active_engagement, reg)
        status = orch.status()
        assert status.agent_count == 1
        assert status.healthy_agents == 1

    def test_register_multiple_agents(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        for _ in range(10):
            orch.register_agent(active_engagement, _make_agent())
        assert orch.status().agent_count == 10

    def test_deregister_agent_removes_from_status(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        reg = _make_agent()
        orch.register_agent(active_engagement, reg)
        orch.deregister_agent(active_engagement, reg.agent_id)
        assert orch.status().agent_count == 0

    def test_reload_from_db_repopulates_registry(
        self, queue: MemoryTaskQueue, active_engagement: str
    ) -> None:
        orch1 = Orchestrator(queue)
        reg = _make_agent()
        orch1.register_agent(active_engagement, reg)

        # New orchestrator instance — starts empty, then reloads
        orch2 = Orchestrator(queue)
        assert orch2.status().agent_count == 0
        orch2.reload_from_db()
        assert orch2.status().agent_count == 1


# ---------------------------------------------------------------------------
# Task lifecycle
# ---------------------------------------------------------------------------


class TestTaskLifecycle:
    def test_submit_task_increments_queue_depth(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        orch.register_agent(active_engagement, _make_agent())
        task = _make_task(active_engagement)
        orch.submit_task(active_engagement, task)
        assert orch.status().queue_depth == 1

    def test_dispatch_assigns_capable_agent(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        reg = _make_agent(capability="port_scan")
        orch.register_agent(active_engagement, reg)
        task = _make_task(active_engagement, capability="port_scan")
        orch.submit_task(active_engagement, task)

        dispatched = orch.dispatch_next()
        assert dispatched is not None
        assert dispatched.status == TaskStatus.ASSIGNED
        assert dispatched.assigned_agent_id == reg.agent_id

    def test_dispatch_requeues_when_no_capable_agent(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        # Register agent with different capability
        reg = _make_agent(capability="vuln_scan")
        orch.register_agent(active_engagement, reg)
        task = _make_task(active_engagement, capability="port_scan")
        orch.submit_task(active_engagement, task)

        dispatched = orch.dispatch_next()
        assert dispatched is None
        # Task should be re-queued
        assert orch.status().queue_depth == 1

    def test_complete_task_sets_completed_status(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        reg = _make_agent()
        orch.register_agent(active_engagement, reg)
        task = _make_task(active_engagement)
        task_id = orch.submit_task(active_engagement, task)
        orch.dispatch_next()

        completed = orch.complete_task(
            active_engagement,
            task_id,
            result={"open_ports": [22, 80, 443]},
        )
        assert completed.status == TaskStatus.COMPLETED
        assert completed.result == {"open_ports": [22, 80, 443]}

    def test_complete_task_sets_failed_status_on_error(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        reg = _make_agent()
        orch.register_agent(active_engagement, reg)
        task = _make_task(active_engagement)
        task_id = orch.submit_task(active_engagement, task)
        orch.dispatch_next()

        failed = orch.complete_task(
            active_engagement,
            task_id,
            error="Connection refused",
        )
        assert failed.status == TaskStatus.FAILED
        assert failed.error == "Connection refused"


# ---------------------------------------------------------------------------
# Workflow submission
# ---------------------------------------------------------------------------


class TestWorkflow:
    def test_submit_workflow_enqueues_all_tasks(
        self, orch: Orchestrator, active_engagement: str
    ) -> None:
        reg = _make_agent()
        orch.register_agent(active_engagement, reg)

        tasks = [_make_task(active_engagement) for _ in range(3)]
        workflow = Workflow(
            workflow_id=make_workflow_id(),
            engagement_id=active_engagement,
            name="recon-workflow",
            task_ids=[t.task_id for t in tasks],
        )
        wf_id = orch.submit_workflow(active_engagement, workflow, tasks)
        assert wf_id == workflow.workflow_id
        assert orch.status().queue_depth == 3


# ---------------------------------------------------------------------------
# Stale agent pruning
# ---------------------------------------------------------------------------


class TestStaleAgentPruning:
    def test_prune_stale_agents(
        self, orch: Orchestrator, queue: MemoryTaskQueue, active_engagement: str
    ) -> None:
        reg = _make_agent()
        orch.register_agent(active_engagement, reg)
        assert orch.status().agent_count == 1

        # Force the heartbeat to appear stale by backdating it in the queue
        import time
        queue._heartbeats[reg.agent_id] = time.time() - 60  # 60s ago

        pruned = orch.prune_stale_agents(max_age_seconds=30)
        assert reg.agent_id in pruned
        assert orch.status().agent_count == 0


# ---------------------------------------------------------------------------
# Orchestrator status
# ---------------------------------------------------------------------------


class TestOrchestratorStatus:
    def test_status_returns_zeros_on_empty_state(self, orch: Orchestrator) -> None:
        s = orch.status()
        assert s.agent_count == 0
        assert s.healthy_agents == 0
        assert s.pending_tasks == 0
        assert s.running_tasks == 0
        assert s.queue_depth == 0

    def test_heartbeat_does_not_require_auth(self, orch: Orchestrator) -> None:
        """agent_heartbeat should not raise even for unknown agent IDs."""
        orch.agent_heartbeat("some-agent-id")  # must not raise
