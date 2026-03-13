"""MCP server entry point for the multi-agent orchestration framework.

Exposes seven tools via the Model Context Protocol (stdio transport):

    register_agent      — add an agent to the pool
    deregister_agent    — remove an agent from the pool
    submit_task         — enqueue a task for dispatch
    complete_task       — report task result / failure
    submit_workflow     — enqueue an ordered batch of tasks
    agent_heartbeat     — update an agent's liveness timestamp
    orchestrator_status — read-only health snapshot (no auth required)

All write operations enforce the engagement authorization gate from auth.py.
PermissionError → MCP error -32600 (Invalid Request)
All other exceptions → MCP error -32603 (Internal Error)
"""
from __future__ import annotations

import asyncio
import json
import logging
import sys
from typing import Any

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import (
    CallToolResult,
    TextContent,
    Tool,
)

from parrot_mcp_server.db import init_db
from parrot_mcp_server.models import (
    AgentCapability,
    AgentRegistration,
    Task,
    TaskStatus,
    Workflow,
)
from parrot_mcp_server.orchestrator import Orchestrator, make_task_id, make_workflow_id
from parrot_mcp_server.queue import create_queue

# ---------------------------------------------------------------------------
# Logging — structured format matching the project convention
# ---------------------------------------------------------------------------

logging.basicConfig(
    stream=sys.stderr,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Global orchestrator instance (initialised in main())
# ---------------------------------------------------------------------------

_orchestrator: Orchestrator | None = None


def _get_orchestrator() -> Orchestrator:
    if _orchestrator is None:
        raise RuntimeError(
            "Orchestrator not initialised — call main() to start the server"
        )
    return _orchestrator


# ---------------------------------------------------------------------------
# MCP Server
# ---------------------------------------------------------------------------

app = Server("parrot-mcp")


@app.list_tools()
async def list_tools() -> list[Tool]:
    """Advertise all orchestration tools to MCP clients."""
    return [
        Tool(
            name="register_agent",
            description=(
                "Register an AI agent in the orchestration pool with its capabilities. "
                "Requires an active engagement — the agent_id is checked against the "
                "engagement scope."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "engagement_id": {"type": "string", "description": "Active engagement ID"},
                    "agent_id": {"type": "string", "description": "Unique agent identifier"},
                    "name": {"type": "string", "description": "Human-readable agent name"},
                    "capabilities": {
                        "type": "array",
                        "description": "List of capabilities the agent provides",
                        "items": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string"},
                                "description": {"type": "string"},
                                "parameters": {"type": "object"},
                            },
                            "required": ["name", "description"],
                        },
                    },
                    "endpoint": {
                        "type": "string",
                        "description": "Optional callback URL for push-style result delivery",
                    },
                },
                "required": ["engagement_id", "agent_id", "name", "capabilities"],
            },
        ),
        Tool(
            name="deregister_agent",
            description="Remove an agent from the orchestration pool (soft-delete for audit).",
            inputSchema={
                "type": "object",
                "properties": {
                    "engagement_id": {"type": "string"},
                    "agent_id": {"type": "string"},
                },
                "required": ["engagement_id", "agent_id"],
            },
        ),
        Tool(
            name="submit_task",
            description=(
                "Enqueue a task for dispatch to a capable agent. The target is "
                "scope-checked against the engagement before queuing."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "engagement_id": {"type": "string"},
                    "task_id": {
                        "type": "string",
                        "description": "Optional — generated if omitted",
                    },
                    "capability_required": {
                        "type": "string",
                        "description": "Name of the AgentCapability needed",
                    },
                    "target": {
                        "type": "string",
                        "description": "Host/CIDR/asset being tested — must be in engagement scope",
                    },
                    "payload": {
                        "type": "object",
                        "description": "Tool-specific parameters passed to the agent",
                    },
                },
                "required": ["engagement_id", "capability_required", "target"],
            },
        ),
        Tool(
            name="complete_task",
            description="Report the result or failure of a previously submitted task.",
            inputSchema={
                "type": "object",
                "properties": {
                    "engagement_id": {"type": "string"},
                    "task_id": {"type": "string"},
                    "result": {
                        "type": "object",
                        "description": "Structured result data (on success)",
                    },
                    "error": {
                        "type": "string",
                        "description": "Error message (on failure)",
                    },
                },
                "required": ["engagement_id", "task_id"],
            },
        ),
        Tool(
            name="submit_workflow",
            description=(
                "Submit an ordered sequence of tasks as a named workflow. "
                "All tasks are individually scope-checked and enqueued."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "engagement_id": {"type": "string"},
                    "workflow_id": {
                        "type": "string",
                        "description": "Optional — generated if omitted",
                    },
                    "name": {"type": "string", "description": "Human-readable workflow name"},
                    "tasks": {
                        "type": "array",
                        "description": "Ordered list of task definitions",
                        "items": {
                            "type": "object",
                            "properties": {
                                "task_id": {"type": "string"},
                                "capability_required": {"type": "string"},
                                "target": {"type": "string"},
                                "payload": {"type": "object"},
                            },
                            "required": ["capability_required", "target"],
                        },
                    },
                },
                "required": ["engagement_id", "name", "tasks"],
            },
        ),
        Tool(
            name="agent_heartbeat",
            description=(
                "Signal that an agent is alive. Agents that miss heartbeats for "
                "longer than the stale threshold are removed from the pool. "
                "No engagement auth required."
            ),
            inputSchema={
                "type": "object",
                "properties": {
                    "agent_id": {"type": "string"},
                },
                "required": ["agent_id"],
            },
        ),
        Tool(
            name="orchestrator_status",
            description=(
                "Return a read-only snapshot of orchestrator health: agent counts, "
                "task queue depth, and pending/running task counts. No auth required."
            ),
            inputSchema={
                "type": "object",
                "properties": {},
                "required": [],
            },
        ),
    ]


@app.call_tool()
async def call_tool(name: str, arguments: dict[str, Any]) -> list[TextContent]:
    """Route an MCP tool call to the appropriate orchestrator method."""
    orch = _get_orchestrator()
    try:
        result = await asyncio.to_thread(_dispatch, orch, name, arguments)
        return [TextContent(type="text", text=json.dumps(result, default=str))]
    except PermissionError as exc:
        # Engagement auth violation → Invalid Request
        logger.warning("Authorization denied for tool '%s': %s", name, exc)
        raise ValueError(f"Authorization denied: {exc}") from exc
    except Exception as exc:
        logger.exception("Internal error in tool '%s'", name)
        raise RuntimeError(f"Internal error: {exc}") from exc


def _dispatch(orch: Orchestrator, name: str, args: dict[str, Any]) -> Any:
    """Synchronous dispatcher — called via asyncio.to_thread."""

    if name == "register_agent":
        caps = [
            AgentCapability(
                name=c["name"],
                description=c["description"],
                parameters=c.get("parameters", {}),
            )
            for c in args.get("capabilities", [])
        ]
        reg = AgentRegistration(
            agent_id=args["agent_id"],
            name=args["name"],
            capabilities=caps,
            endpoint=args.get("endpoint"),
        )
        agent_id = orch.register_agent(args["engagement_id"], reg)
        return {"agent_id": agent_id, "status": "registered"}

    if name == "deregister_agent":
        orch.deregister_agent(args["engagement_id"], args["agent_id"])
        return {"agent_id": args["agent_id"], "status": "deregistered"}

    if name == "submit_task":
        task = Task(
            task_id=args.get("task_id") or make_task_id(),
            engagement_id=args["engagement_id"],
            capability_required=args["capability_required"],
            target=args["target"],
            payload=args.get("payload", {}),
        )
        task_id = orch.submit_task(args["engagement_id"], task)
        return {"task_id": task_id, "status": "queued"}

    if name == "complete_task":
        task = orch.complete_task(
            engagement_id=args["engagement_id"],
            task_id=args["task_id"],
            result=args.get("result"),
            error=args.get("error"),
        )
        return {"task_id": task.task_id, "status": task.status.value}

    if name == "submit_workflow":
        workflow_id = args.get("workflow_id") or make_workflow_id()
        task_objects: list[Task] = []
        task_ids: list[str] = []
        for t in args.get("tasks", []):
            tid = t.get("task_id") or make_task_id()
            task_objects.append(
                Task(
                    task_id=tid,
                    engagement_id=args["engagement_id"],
                    capability_required=t["capability_required"],
                    target=t["target"],
                    payload=t.get("payload", {}),
                )
            )
            task_ids.append(tid)
        workflow = Workflow(
            workflow_id=workflow_id,
            engagement_id=args["engagement_id"],
            name=args["name"],
            task_ids=task_ids,
        )
        wf_id = orch.submit_workflow(args["engagement_id"], workflow, task_objects)
        return {"workflow_id": wf_id, "task_ids": task_ids, "status": "queued"}

    if name == "agent_heartbeat":
        orch.agent_heartbeat(args["agent_id"])
        return {"agent_id": args["agent_id"], "status": "ok"}

    if name == "orchestrator_status":
        s = orch.status()
        return s.model_dump()

    raise ValueError(f"Unknown tool: {name!r}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------


def main() -> None:
    """Start the MCP server (stdio transport)."""
    logger.info("Initialising Parrot MCP Server — multi-agent orchestration")

    init_db()
    queue = create_queue()

    global _orchestrator
    _orchestrator = Orchestrator(queue)
    _orchestrator.reload_from_db()

    logger.info("MCP server ready — awaiting connections on stdio")
    asyncio.run(stdio_server(app))
