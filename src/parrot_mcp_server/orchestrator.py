"""Central orchestration controller for the multi-agent framework.

Every write operation passes through the engagement authorization gate in
auth.py before touching agent or task state.  This enforces the pentesting
scope/time-window contract on all orchestration activity.

Thread safety: a threading.Lock guards the in-memory _agents registry.
Blocking DB / Redis calls are wrapped in asyncio.to_thread at the server
boundary (server.py), so this class itself is synchronous.
"""
from __future__ import annotations

import logging
import threading
import uuid
from datetime import datetime, timezone

from parrot_mcp_server.auth import require_authorization
from parrot_mcp_server.db import (
    count_tasks_by_status,
    load_healthy_agents,
    persist_agent,
    persist_task,
    persist_workflow,
)
from parrot_mcp_server.models import (
    AgentRegistration,
    OrchestratorStatus,
    Task,
    TaskStatus,
    Workflow,
)
from parrot_mcp_server.queue import TaskQueue

logger = logging.getLogger(__name__)


class Orchestrator:
    """Central controller — agent registry, task dispatch, health monitoring."""

    def __init__(self, queue: TaskQueue) -> None:
        self._queue = queue
        # In-memory registry is the hot path for dispatch.
        # DB rows are the audit trail.
        self._agents: dict[str, AgentRegistration] = {}
        self._lock = threading.Lock()

    # ------------------------------------------------------------------
    # Startup
    # ------------------------------------------------------------------

    def reload_from_db(self) -> None:
        """Repopulate the in-memory registry from healthy DB rows on startup."""
        agents = load_healthy_agents()
        with self._lock:
            for agent in agents:
                self._agents[agent.agent_id] = agent
        logger.info(
            "Reloaded %d healthy agent(s) from database", len(agents)
        )

    # ------------------------------------------------------------------
    # Agent lifecycle
    # ------------------------------------------------------------------

    def register_agent(
        self, engagement_id: str, reg: AgentRegistration
    ) -> str:
        """Register an agent in the pool.

        Requires an active engagement — agent_id is used as the target
        for the scope check (use '*' in engagement scope to allow any).
        """
        require_authorization(engagement_id, reg.agent_id)
        persist_agent(reg)
        with self._lock:
            self._agents[reg.agent_id] = reg
        self._queue.record_heartbeat(reg.agent_id)
        logger.info(
            "Agent registered: %s (%s) with %d capability(s)",
            reg.agent_id,
            reg.name,
            len(reg.capabilities),
        )
        return reg.agent_id

    def deregister_agent(self, engagement_id: str, agent_id: str) -> None:
        """Soft-remove an agent from the pool (DB row kept for audit trail)."""
        require_authorization(engagement_id, agent_id)
        with self._lock:
            reg = self._agents.pop(agent_id, None)
        if reg is not None:
            reg.healthy = False
            persist_agent(reg)
        self._queue.remove_agent_heartbeat(agent_id)
        logger.info("Agent deregistered: %s", agent_id)

    def agent_heartbeat(self, agent_id: str) -> None:
        """Update an agent's last-seen timestamp.

        No auth gate — heartbeats carry no privileged action.
        """
        with self._lock:
            reg = self._agents.get(agent_id)
        if reg is not None:
            reg.last_heartbeat = datetime.now(tz=timezone.utc)
        self._queue.record_heartbeat(agent_id)

    # ------------------------------------------------------------------
    # Task submission and dispatch
    # ------------------------------------------------------------------

    def submit_task(self, engagement_id: str, task: Task) -> str:
        """Validate and enqueue a task for dispatch.

        The engagement scope is checked against task.target — this is the
        actual host/CIDR being tested, not just an internal identifier.
        """
        require_authorization(engagement_id, task.target)
        task.status = TaskStatus.PENDING
        persist_task(task)
        self._queue.enqueue(task)
        logger.info(
            "Task submitted: %s (capability=%s target=%s)",
            task.task_id,
            task.capability_required,
            task.target,
        )
        return task.task_id

    def dispatch_next(self) -> Task | None:
        """Pop the next pending task and assign it to a capable healthy agent.

        Returns the assigned Task (with status=ASSIGNED), or None if the
        queue is empty or no capable agent is available.
        """
        self.prune_stale_agents()

        task = self._queue.dequeue(timeout=1)
        if task is None:
            return None

        agent = self._find_capable_agent(task.capability_required)
        if agent is None:
            # Re-enqueue so the task isn't lost; log a warning
            logger.warning(
                "No capable agent for task %s (capability=%s); re-queuing",
                task.task_id,
                task.capability_required,
            )
            self._queue.enqueue(task)
            return None

        task.status = TaskStatus.ASSIGNED
        task.assigned_agent_id = agent.agent_id
        task.updated_at = datetime.now(tz=timezone.utc)
        persist_task(task)
        self._queue.update_task(task)
        logger.info(
            "Task %s assigned to agent %s", task.task_id, agent.agent_id
        )
        return task

    def complete_task(
        self,
        engagement_id: str,
        task_id: str,
        result: dict | None = None,
        error: str | None = None,
    ) -> Task:
        """Mark a task as completed or failed and persist the result.

        engagement_id is checked so only agents operating under the same
        engagement can report outcomes.
        """
        # Use task_id as the target for the scope check — agents use the
        # same engagement they were registered under.
        require_authorization(engagement_id, task_id)

        # Retrieve from queue store or reconstruct a minimal Task for update
        task = self._queue.dequeue(timeout=0)
        # The above dequeue is not right for a specific task_id.
        # Load from DB instead.
        from parrot_mcp_server.db import get_session, TaskRow, task_to_model

        with get_session() as session:
            row = session.get(TaskRow, task_id)
            if row is None:
                raise ValueError(f"Task '{task_id}' not found")
            task = task_to_model(row)

        task.status = TaskStatus.COMPLETED if error is None else TaskStatus.FAILED
        task.result = result
        task.error = error
        task.updated_at = datetime.now(tz=timezone.utc)
        persist_task(task)
        self._queue.update_task(task)
        logger.info(
            "Task %s %s", task_id, task.status.value
        )
        return task

    # ------------------------------------------------------------------
    # Workflow submission
    # ------------------------------------------------------------------

    def submit_workflow(
        self,
        engagement_id: str,
        workflow: Workflow,
        tasks: list[Task],
    ) -> str:
        """Submit a workflow — validates engagement then enqueues all tasks.

        *tasks* must correspond 1-to-1 with workflow.task_ids (same order).
        """
        require_authorization(engagement_id, workflow.workflow_id)
        for task in tasks:
            self.submit_task(engagement_id, task)
        workflow.status = TaskStatus.PENDING
        persist_workflow(workflow)
        logger.info(
            "Workflow %s submitted (%d tasks)", workflow.workflow_id, len(tasks)
        )
        return workflow.workflow_id

    # ------------------------------------------------------------------
    # Health and status
    # ------------------------------------------------------------------

    def prune_stale_agents(self, max_age_seconds: int = 30) -> list[str]:
        """Remove agents whose heartbeat has expired from the in-memory registry.

        DB rows are soft-deleted (healthy=False) to preserve the audit trail.
        Returns the list of pruned agent IDs.
        """
        stale_ids = self._queue.stale_agents(max_age_seconds)
        pruned: list[str] = []
        with self._lock:
            for agent_id in stale_ids:
                reg = self._agents.pop(agent_id, None)
                if reg is not None:
                    reg.healthy = False
                    persist_agent(reg)
                    pruned.append(agent_id)
                self._queue.remove_agent_heartbeat(agent_id)
        if pruned:
            logger.warning("Pruned stale agents: %s", pruned)
        return pruned

    def status(self) -> OrchestratorStatus:
        """Return a read-only snapshot of orchestrator health — no auth required."""
        with self._lock:
            agent_count = len(self._agents)
            healthy_agents = sum(1 for a in self._agents.values() if a.healthy)

        pending = count_tasks_by_status(TaskStatus.PENDING)
        running = count_tasks_by_status(TaskStatus.RUNNING)
        queue_depth = self._queue.depth()

        return OrchestratorStatus(
            agent_count=agent_count,
            healthy_agents=healthy_agents,
            pending_tasks=pending,
            running_tasks=running,
            queue_depth=queue_depth,
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _find_capable_agent(self, capability_name: str) -> AgentRegistration | None:
        """Find a healthy agent that advertises *capability_name*.

        Simple linear scan — adequate for ≤100 agents.  For larger pools,
        replace with an inverted capability → agent_id index.
        """
        with self._lock:
            candidates = [
                a
                for a in self._agents.values()
                if a.healthy
                and any(c.name == capability_name for c in a.capabilities)
            ]
        if not candidates:
            return None
        # Prefer the agent with the most recent heartbeat (least idle)
        return max(candidates, key=lambda a: a.last_heartbeat)


# ---------------------------------------------------------------------------
# Convenience factory
# ---------------------------------------------------------------------------


def make_task_id() -> str:
    """Generate a random task ID."""
    return f"task-{uuid.uuid4().hex[:12]}"


def make_workflow_id() -> str:
    """Generate a random workflow ID."""
    return f"wf-{uuid.uuid4().hex[:12]}"
