#!/usr/bin/env bash
# orchestration_cli.sh - Command-line interface for orchestration system
# Provides commands to manage agents, submit tasks, and monitor workflows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/orchestration_lib.sh"

usage() {
	cat <<-EOF
		Usage: $0 COMMAND [OPTIONS]
		
		Multi-Agent Orchestration CLI - Manage agents, tasks, and workflows
		
		COMMANDS:
		  agents list [TYPE]              List all agents (optionally filter by type)
		  agents register ID TYPE         Register a new agent
		  agents deregister ID            Deregister an agent
		  agents status                   Show agent statistics
		
		  tasks submit TYPE PAYLOAD       Submit a new task
		  tasks list [STATUS]             List tasks (pending, assigned, completed, failed)
		  tasks status TASK_ID            Show task status
		  tasks cancel TASK_ID            Cancel a pending task
		
		  workflows submit NAME TASKS     Submit a workflow
		  workflows status WORKFLOW_ID    Show workflow status
		  workflows list                  List all workflows
		
		  results show TASK_ID            Show task result
		  results aggregate TASK_IDS...   Aggregate results from multiple tasks
		
		  system cleanup [DAYS]           Cleanup old tasks (default: 7 days)
		  system stats                    Show system statistics
		
		EXAMPLES:
		  # List all agents
		  $0 agents list
		  
		  # Submit a reconnaissance task
		  $0 tasks submit port_scan '{"target":"192.168.1.1"}'
		  
		  # Submit a workflow with multiple tasks
		  $0 workflows submit "security_audit" '[{"type":"port_scan"},{"type":"vuln_scan"}]'
		  
		  # Show task result
		  $0 results show task_1234567890_5678
		  
		  # Cleanup old tasks
		  $0 system cleanup 7
	EOF
}

# Agent commands
cmd_agents() {
	local subcmd="${1:-}"
	shift || true
	
	case "$subcmd" in
		list)
			local agent_type="${1:-}"
			echo "Active Agents:"
			echo "=============="
			
			local agents
			agents=$(orch_list_agents "$agent_type")
			
			if [ -z "$agents" ]; then
				echo "No agents registered"
				return 0
			fi
			
			for agent_id in $agents; do
				local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
				if [ -f "$agent_file" ]; then
					if command -v jq &>/dev/null; then
						echo ""
						echo "Agent ID: $agent_id"
						jq -r '"  Type: \(.agent_type)\n  Status: \(.status)\n  Registered: \(.registered_at)\n  Last Heartbeat: \(.last_heartbeat)\n  Tasks Completed: \(.tasks_completed)\n  Tasks Failed: \(.tasks_failed)"' "$agent_file"
					else
						echo ""
						echo "Agent: $agent_id"
						cat "$agent_file"
					fi
				fi
			done
			;;
		
		register)
			local agent_id="$1"
			local agent_type="$2"
			local capabilities='["custom"]'
			
			if orch_register_agent "$agent_id" "$agent_type" "$capabilities"; then
				echo "Agent registered: $agent_id"
			else
				echo "Failed to register agent" >&2
				return 1
			fi
			;;
		
		deregister)
			local agent_id="$1"
			
			if orch_deregister_agent "$agent_id"; then
				echo "Agent deregistered: $agent_id"
			else
				echo "Failed to deregister agent" >&2
				return 1
			fi
			;;
		
		status)
			local agent_count
			agent_count=$(find "${ORCH_AGENTS_DIR}" -name "*.json" -type f 2>/dev/null | wc -l)
			
			echo "Agent Statistics:"
			echo "================="
			echo "Active agents: $agent_count"
			echo ""
			echo "By type:"
			
			for agent_type in recon exploitation reporting generic; do
				local count
				count=$(orch_list_agents "$agent_type" | wc -w)
				if [ "$count" -gt 0 ]; then
					echo "  $agent_type: $count"
				fi
			done
			;;
		
		*)
			echo "Unknown agents subcommand: $subcmd" >&2
			usage
			return 1
			;;
	esac
}

# Task commands
cmd_tasks() {
	local subcmd="${1:-}"
	shift || true
	
	case "$subcmd" in
		submit)
			local task_type="$1"
			local task_payload="$2"
			local capability="${3:-any}"
			local priority="${4:-5}"
			
			local task_id
			if task_id=$(orch_submit_task "$task_type" "$task_payload" "$capability" "$priority"); then
				echo "Task submitted: $task_id"
			else
				echo "Failed to submit task" >&2
				return 1
			fi
			;;
		
		list)
			local status_filter="${1:-}"
			echo "Tasks:"
			echo "======"
			
			local count=0
			for task_file in "${ORCH_TASKS_DIR}"/*.json; do
				[ -f "$task_file" ] || continue
				
				if [ -n "$status_filter" ]; then
					if ! grep -q "\"status\": \"$status_filter\"" "$task_file"; then
						continue
					fi
				fi
				
				local task_id
				task_id=$(basename "$task_file" .json)
				
				if command -v jq &>/dev/null; then
					echo ""
					echo "Task ID: $task_id"
					jq -r '"  Type: \(.task_type)\n  Status: \(.status)\n  Priority: \(.priority)\n  Submitted: \(.submitted_at)\n  Assigned Agent: \(.assigned_agent // "none")"' "$task_file"
				else
					echo ""
					echo "Task: $task_id"
					cat "$task_file"
				fi
				
				count=$((count + 1))
			done
			
			if [ "$count" -eq 0 ]; then
				echo "No tasks found"
			fi
			;;
		
		status)
			local task_id="$1"
			local task_file="${ORCH_TASKS_DIR}/${task_id}.json"
			
			if [ ! -f "$task_file" ]; then
				# Check completed/failed archives
				if [ -f "${task_file}.completed" ]; then
					task_file="${task_file}.completed"
				elif [ -f "${task_file}.failed" ]; then
					task_file="${task_file}.failed"
				else
					echo "Task not found: $task_id" >&2
					return 1
				fi
			fi
			
			echo "Task Status: $task_id"
			echo "===================="
			
			if command -v jq &>/dev/null; then
				jq '.' "$task_file"
			else
				cat "$task_file"
			fi
			;;
		
		cancel)
			local task_id="$1"
			local task_file="${ORCH_TASKS_DIR}/${task_id}.json"
			
			if [ ! -f "$task_file" ]; then
				echo "Task not found: $task_id" >&2
				return 1
			fi
			
			# Only cancel pending tasks
			if ! grep -q '"status": "pending"' "$task_file"; then
				echo "Task is not pending (cannot cancel)" >&2
				return 1
			fi
			
			rm -f "$task_file"
			echo "Task cancelled: $task_id"
			;;
		
		*)
			echo "Unknown tasks subcommand: $subcmd" >&2
			usage
			return 1
			;;
	esac
}

# Workflow commands
cmd_workflows() {
	local subcmd="${1:-}"
	shift || true
	
	case "$subcmd" in
		submit)
			local workflow_name="$1"
			local workflow_tasks="$2"
			
			local workflow_id
			if workflow_id=$(orch_submit_workflow "$workflow_name" "$workflow_tasks"); then
				echo "Workflow submitted: $workflow_id"
			else
				echo "Failed to submit workflow" >&2
				return 1
			fi
			;;
		
		status)
			local workflow_id="$1"
			
			echo "Workflow Status: $workflow_id"
			echo "========================="
			
			if orch_get_workflow_status "$workflow_id"; then
				return 0
			else
				return 1
			fi
			;;
		
		list)
			echo "Workflows:"
			echo "=========="
			
			local count=0
			for workflow_file in "${ORCH_STATE_DIR}"/workflow_*.json; do
				[ -f "$workflow_file" ] || continue
				
				local workflow_id
				workflow_id=$(basename "$workflow_file" .json | sed 's/workflow_//')
				
				if command -v jq &>/dev/null; then
					echo ""
					echo "Workflow ID: $workflow_id"
					jq -r '"  Name: \(.workflow_name)\n  Status: \(.status)\n  Submitted: \(.submitted_at)"' "$workflow_file"
				else
					echo ""
					echo "Workflow: $workflow_id"
					grep -E '"workflow_name"|"status"|"submitted_at"' "$workflow_file"
				fi
				
				count=$((count + 1))
			done
			
			if [ "$count" -eq 0 ]; then
				echo "No workflows found"
			fi
			;;
		
		*)
			echo "Unknown workflows subcommand: $subcmd" >&2
			usage
			return 1
			;;
	esac
}

# Results commands
cmd_results() {
	local subcmd="${1:-}"
	shift || true
	
	case "$subcmd" in
		show)
			local task_id="$1"
			local result_file="${ORCH_RESULTS_DIR}/${task_id}_result.json"
			
			if [ ! -f "$result_file" ]; then
				echo "Result not found for task: $task_id" >&2
				return 1
			fi
			
			echo "Task Result: $task_id"
			echo "===================="
			
			if command -v jq &>/dev/null; then
				jq '.' "$result_file"
			else
				cat "$result_file"
			fi
			;;
		
		aggregate)
			local task_ids="$*"
			
			if [ -z "$task_ids" ]; then
				echo "No task IDs provided" >&2
				return 1
			fi
			
			local aggregated_file
			if aggregated_file=$(orch_aggregate_results $task_ids); then
				echo "Results aggregated: $aggregated_file"
				
				if command -v jq &>/dev/null; then
					jq '.' "$aggregated_file"
				else
					cat "$aggregated_file"
				fi
			else
				echo "Failed to aggregate results" >&2
				return 1
			fi
			;;
		
		*)
			echo "Unknown results subcommand: $subcmd" >&2
			usage
			return 1
			;;
	esac
}

# System commands
cmd_system() {
	local subcmd="${1:-}"
	shift || true
	
	case "$subcmd" in
		cleanup)
			local days="${1:-7}"
			
			echo "Cleaning up tasks older than $days days..."
			orch_cleanup_old_tasks "$days"
			echo "Cleanup complete"
			;;
		
		stats)
			echo "Orchestration System Statistics:"
			echo "================================"
			echo ""
			
			# Agent stats
			local agent_count
			agent_count=$(find "${ORCH_AGENTS_DIR}" -name "*.json" -type f 2>/dev/null | wc -l)
			echo "Active agents: $agent_count"
			
			# Task stats
			local pending_tasks
			pending_tasks=$(grep -l '"status": "pending"' "${ORCH_TASKS_DIR}"/*.json 2>/dev/null | wc -l)
			echo "Pending tasks: $pending_tasks"
			
			local assigned_tasks
			assigned_tasks=$(grep -l '"status": "assigned"' "${ORCH_TASKS_DIR}"/*.json 2>/dev/null | wc -l)
			echo "Assigned tasks: $assigned_tasks"
			
			local completed_tasks
			completed_tasks=$(find "${ORCH_TASKS_DIR}" -name "*.completed" -type f 2>/dev/null | wc -l)
			echo "Completed tasks: $completed_tasks"
			
			local failed_tasks
			failed_tasks=$(find "${ORCH_TASKS_DIR}" -name "*.failed" -type f 2>/dev/null | wc -l)
			echo "Failed tasks: $failed_tasks"
			
			# Workflow stats
			local workflow_count
			workflow_count=$(find "${ORCH_STATE_DIR}" -name "workflow_*.json" -type f 2>/dev/null | wc -l)
			echo "Active workflows: $workflow_count"
			
			# Result stats
			local result_count
			result_count=$(find "${ORCH_RESULTS_DIR}" -name "*_result.json" -type f 2>/dev/null | wc -l)
			echo "Results stored: $result_count"
			;;
		
		*)
			echo "Unknown system subcommand: $subcmd" >&2
			usage
			return 1
			;;
	esac
}

# Main command router
main() {
	if [ $# -eq 0 ]; then
		usage
		exit 1
	fi
	
	local command="$1"
	shift
	
	case "$command" in
		agents)
			cmd_agents "$@"
			;;
		tasks)
			cmd_tasks "$@"
			;;
		workflows)
			cmd_workflows "$@"
			;;
		results)
			cmd_results "$@"
			;;
		system)
			cmd_system "$@"
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			echo "Unknown command: $command" >&2
			usage
			exit 1
			;;
	esac
}

main "$@"
