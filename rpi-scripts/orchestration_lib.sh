#!/usr/bin/env bash
# orchestration_lib.sh - Multi-Agent Orchestration Library
# Provides core functions for agent coordination, task management, and workflow execution

set -euo pipefail

# Source common configuration if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/common_config.sh" ]; then
	source "${SCRIPT_DIR}/common_config.sh"
fi

# Orchestration directories
ORCH_BASE_DIR="${ORCH_BASE_DIR:-${SCRIPT_DIR}/orchestration}"
ORCH_AGENTS_DIR="${ORCH_AGENTS_DIR:-${ORCH_BASE_DIR}/agents}"
ORCH_TASKS_DIR="${ORCH_TASKS_DIR:-${ORCH_BASE_DIR}/tasks}"
ORCH_RESULTS_DIR="${ORCH_RESULTS_DIR:-${ORCH_BASE_DIR}/results}"
ORCH_STATE_DIR="${ORCH_STATE_DIR:-${ORCH_BASE_DIR}/state}"

# Lock directory for atomic operations
ORCH_LOCK_DIR="${ORCH_LOCK_DIR:-${ORCH_BASE_DIR}/.locks}"

# Ensure directories exist
mkdir -p "$ORCH_AGENTS_DIR" "$ORCH_TASKS_DIR" "$ORCH_RESULTS_DIR" "$ORCH_STATE_DIR" "$ORCH_LOCK_DIR"

# Logging function (falls back to echo if parrot_log not available)
orch_log() {
	local level="$1"
	shift
	local message="$*"
	local timestamp
	timestamp=$(date '+%Y-%m-%d %H:%M:%S')
	local msgid
	msgid=$(date +%s%N)
	
	if command -v parrot_log &>/dev/null; then
		parrot_log "$level" "$message"
	else
		echo "[$timestamp] [$level] [msgid:$msgid] $message" >&2
	fi
}

# Acquire lock for atomic operations
orch_acquire_lock() {
	local lock_name="$1"
	local lock_file="${ORCH_LOCK_DIR}/${lock_name}.lock"
	local timeout="${2:-30}"
	local start_time
	start_time=$(date +%s)
	
	while ! mkdir "$lock_file" 2>/dev/null; do
		local current_time
		current_time=$(date +%s)
		if [ $((current_time - start_time)) -gt "$timeout" ]; then
			orch_log "ERROR" "Failed to acquire lock: $lock_name (timeout)"
			return 1
		fi
		sleep 0.1
	done
	
	# Store PID in lock file for debugging
	echo $$ > "${lock_file}/pid"
	return 0
}

# Release lock
orch_release_lock() {
	local lock_name="$1"
	local lock_file="${ORCH_LOCK_DIR}/${lock_name}.lock"
	
	if [ -d "$lock_file" ]; then
		# Verify ownership before releasing the lock
		if [ -f "${lock_file}/pid" ]; then
			local lock_owner
			lock_owner=$(cat "${lock_file}/pid" 2>/dev/null || echo "")
			if [ "$lock_owner" != "$$" ]; then
				orch_log "WARN" "Attempting to release lock '$lock_name' owned by PID $lock_owner (current PID: $$)"
				return 1
			fi
		fi
		rm -rf "$lock_file"
	fi
}

# Generate unique ID
orch_generate_id() {
	local prefix="${1:-item}"
	echo "${prefix}_$(date +%s%N)_$$"
}

# Agent Registration: Register a new agent with capabilities
orch_register_agent() {
	local agent_id="$1"
	local agent_type="$2"  # e.g., recon, exploitation, reporting
	local capabilities="$3"  # JSON array of capabilities
	
	if [ -z "$agent_id" ] || [ -z "$agent_type" ]; then
		orch_log "ERROR" "Agent ID and type are required"
		return 1
	fi

	# Validate agent_id - allow only alphanumeric, underscore, hyphen
	if ! [[ "$agent_id" =~ ^[a-zA-Z0-9_-]+$ ]]; then
		orch_log "ERROR" "Invalid agent ID: must contain only alphanumeric characters, underscore, or hyphen"
		return 1
	fi
	
	local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
	
	# Acquire lock for agent registration
	if ! orch_acquire_lock "agent_registry"; then
		return 1
	fi
	
	# Create agent registration file
	cat > "$agent_file" <<-EOF
	{
	  "agent_id": "$agent_id",
	  "agent_type": "$agent_type",
	  "capabilities": $capabilities,
	  "status": "active",
	  "registered_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
	  "last_heartbeat": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
	  "pid": $$,
	  "tasks_completed": 0,
	  "tasks_failed": 0
	}
	EOF
	
	orch_release_lock "agent_registry"
	
	orch_log "INFO" "Agent registered: $agent_id (type: $agent_type)"
	return 0
}

# Agent Deregistration: Remove agent from registry
orch_deregister_agent() {
	local agent_id="$1"
	
	if [ -z "$agent_id" ]; then
		orch_log "ERROR" "Agent ID is required"
		return 1
	fi
	
	local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
	
	if [ ! -f "$agent_file" ]; then
		orch_log "WARN" "Agent not found: $agent_id"
		return 1
	fi
	
	# Acquire lock
	if ! orch_acquire_lock "agent_registry"; then
		return 1
	fi
	
	# Mark as inactive before removing
	if command -v jq &>/dev/null; then
		local timestamp
		timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
		jq '.status = "inactive" | .deregistered_at = "'"$timestamp"'"' "$agent_file" > "${agent_file}.tmp"
		mv "${agent_file}.tmp" "${agent_file}.inactive"
		rm -f "$agent_file"
	else
		mv "$agent_file" "${agent_file}.inactive"
	fi
	
	orch_release_lock "agent_registry"
	
	orch_log "INFO" "Agent deregistered: $agent_id"
	return 0
}

# Update agent heartbeat
orch_agent_heartbeat() {
	local agent_id="$1"
	local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
	
	if [ ! -f "$agent_file" ]; then
		orch_log "WARN" "Agent not found for heartbeat: $agent_id"
		return 1
	fi
	
	local timestamp
	timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	
	if command -v jq &>/dev/null; then
		jq '.last_heartbeat = "'"$timestamp"'"' "$agent_file" > "${agent_file}.tmp"
		mv "${agent_file}.tmp" "$agent_file"
	else
		# Simple approach without jq - update timestamp in place
		sed -i 's/"last_heartbeat": "[^"]*"/"last_heartbeat": "'"$timestamp"'"/' "$agent_file"
	fi
	
	return 0
}

# List active agents
orch_list_agents() {
	local agent_type="${1:-}"
	
	for agent_file in "${ORCH_AGENTS_DIR}"/*.json; do
		[ -f "$agent_file" ] || continue
		
		if [ -n "$agent_type" ]; then
			# Filter by type if specified
			if command -v jq &>/dev/null; then
				if jq -e ".agent_type == \"$agent_type\"" "$agent_file" >/dev/null 2>&1; then
					basename "$agent_file" .json
				fi
			else
				# Simple grep fallback
				if grep -q "\"agent_type\": \"$agent_type\"" "$agent_file"; then
					basename "$agent_file" .json
				fi
			fi
		else
			basename "$agent_file" .json
		fi
	done
}

# Task Queue: Submit a task
orch_submit_task() {
	local task_type="$1"
	local task_payload="$2"
	local required_capability="${3:-any}"
	local priority="${4:-5}"  # Priority 1-10, default 5
	
	local task_id
	task_id=$(orch_generate_id "task")
	local task_file="${ORCH_TASKS_DIR}/${task_id}.json"
	
	# Acquire lock
	if ! orch_acquire_lock "task_queue"; then
		return 1
	fi
	
	# Create task file
	cat > "$task_file" <<-EOF
	{
	  "task_id": "$task_id",
	  "task_type": "$task_type",
	  "payload": $task_payload,
	  "required_capability": "$required_capability",
	  "priority": $priority,
	  "status": "pending",
	  "submitted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
	  "assigned_agent": null,
	  "attempts": 0,
	  "max_attempts": 3
	}
	EOF
	
	orch_release_lock "task_queue"
	
	orch_log "INFO" "Task submitted: $task_id (type: $task_type, priority: $priority)"
	echo "$task_id"
	return 0
}

# Task Assignment: Assign task to agent
orch_assign_task() {
	local task_id="$1"
	local agent_id="$2"
	
	local task_file="${ORCH_TASKS_DIR}/${task_id}.json"
	
	if [ ! -f "$task_file" ]; then
		orch_log "ERROR" "Task not found: $task_id"
		return 1
	fi
	
	# Acquire lock
	if ! orch_acquire_lock "task_${task_id}"; then
		return 1
	fi
	
	# Update task status
	local timestamp
	timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	
	if command -v jq &>/dev/null; then
		jq '.status = "assigned" | .assigned_agent = "'"$agent_id"'" | .assigned_at = "'"$timestamp"'"' "$task_file" > "${task_file}.tmp"
		mv "${task_file}.tmp" "$task_file"
	else
		# Fallback without jq
		sed -i 's/"status": "pending"/"status": "assigned"/' "$task_file"
		sed -i 's/"assigned_agent": null/"assigned_agent": "'"$agent_id"'"/' "$task_file"
	fi
	
	orch_release_lock "task_${task_id}"
	
	orch_log "INFO" "Task assigned: $task_id -> $agent_id"
	return 0
}

# Get next available task for agent
orch_get_next_task() {
	local agent_id="$1"
	local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
	
	if [ ! -f "$agent_file" ]; then
		orch_log "ERROR" "Agent not found: $agent_id"
		return 1
	fi
	
	# Get agent capabilities
	local agent_type
	if command -v jq &>/dev/null; then
		agent_type=$(jq -r '.agent_type' "$agent_file")
	else
		agent_type=$(grep '"agent_type"' "$agent_file" | cut -d'"' -f4)
	fi
	
	# Find pending tasks sorted by priority
	local best_task=""
	local best_priority=0
	
	for task_file in "${ORCH_TASKS_DIR}"/*.json; do
		[ -f "$task_file" ] || continue
		
		# Check if task is pending
		if ! grep -q '"status": "pending"' "$task_file"; then
			continue
		fi
		
		# Check capability match
		local required_cap
		if command -v jq &>/dev/null; then
			required_cap=$(jq -r '.required_capability' "$task_file")
		else
			required_cap=$(grep '"required_capability"' "$task_file" | cut -d'"' -f4)
		fi
		
		if [ "$required_cap" != "any" ] && [ "$required_cap" != "$agent_type" ]; then
			continue
		fi
		
		# Check priority
		local priority
		if command -v jq &>/dev/null; then
			priority=$(jq -r '.priority' "$task_file")
		else
			priority=$(grep '"priority"' "$task_file" | cut -d':' -f2 | tr -d ' ,')
		fi
		
		if [ "$priority" -gt "$best_priority" ]; then
			best_priority=$priority
			best_task=$(basename "$task_file" .json)
		fi
	done
	
	if [ -n "$best_task" ]; then
		echo "$best_task"
		return 0
	fi
	
	return 1
}

# Task Completion: Mark task as completed
orch_complete_task() {
	local task_id="$1"
	local result_data="$2"
	local agent_id="$3"
	
	local task_file="${ORCH_TASKS_DIR}/${task_id}.json"
	local result_file="${ORCH_RESULTS_DIR}/${task_id}_result.json"
	
	if [ ! -f "$task_file" ]; then
		orch_log "ERROR" "Task not found: $task_id"
		return 1
	fi
	
	# Acquire lock
	if ! orch_acquire_lock "task_${task_id}"; then
		return 1
	fi
	
	# Update task status
	local timestamp
	timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
	
	if command -v jq &>/dev/null; then
		jq '.status = "completed" | .completed_at = "'"$timestamp"'"' "$task_file" > "${task_file}.tmp"
		mv "${task_file}.tmp" "$task_file"
	else
		sed -i 's/"status": "[^"]*"/"status": "completed"/' "$task_file"
	fi
	
	# Store result
	cat > "$result_file" <<-EOF
	{
	  "task_id": "$task_id",
	  "agent_id": "$agent_id",
	  "result": $result_data,
	  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
	}
	EOF
	
	# Update agent statistics
	if [ -n "$agent_id" ]; then
		local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
		if [ -f "$agent_file" ] && command -v jq &>/dev/null; then
			jq '.tasks_completed = (.tasks_completed + 1)' "$agent_file" > "${agent_file}.tmp"
			mv "${agent_file}.tmp" "$agent_file"
		fi
	fi
	
	# Move completed task to archive
	mv "$task_file" "${task_file}.completed"
	
	orch_release_lock "task_${task_id}"
	
	orch_log "INFO" "Task completed: $task_id (agent: $agent_id)"
	return 0
}

# Task Failure: Mark task as failed
orch_fail_task() {
	local task_id="$1"
	local error_message="$2"
	local agent_id="$3"
	
	local task_file="${ORCH_TASKS_DIR}/${task_id}.json"
	
	if [ ! -f "$task_file" ]; then
		orch_log "ERROR" "Task not found: $task_id"
		return 1
	fi
	
	# Acquire lock
	if ! orch_acquire_lock "task_${task_id}"; then
		return 1
	fi
	
	# Increment attempts
	local attempts
	if command -v jq &>/dev/null; then
		attempts=$(jq -r '.attempts' "$task_file")
		local max_attempts
		max_attempts=$(jq -r '.max_attempts' "$task_file")
		
		attempts=$((attempts + 1))
		
		if [ "$attempts" -ge "$max_attempts" ]; then
			# Mark as failed permanently
			jq '.status = "failed" | .attempts = '$attempts' | .failed_at = "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'" | .error = "'$error_message'"' "$task_file" > "${task_file}.tmp"
			mv "${task_file}.tmp" "$task_file"
			mv "$task_file" "${task_file}.failed"
			orch_log "ERROR" "Task failed permanently: $task_id (attempts: $attempts)"
		else
			# Retry - reset to pending
			jq '.status = "pending" | .attempts = '$attempts' | .assigned_agent = null' "$task_file" > "${task_file}.tmp"
			mv "${task_file}.tmp" "$task_file"
			orch_log "WARN" "Task failed, will retry: $task_id (attempt: $attempts)"
		fi
	else
		# Simple fallback
		attempts=1
		sed -i 's/"status": "[^"]*"/"status": "failed"/' "$task_file"
		mv "$task_file" "${task_file}.failed"
	fi
	
	# Update agent failure count
	if [ -n "$agent_id" ]; then
		local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
		if [ -f "$agent_file" ] && command -v jq &>/dev/null; then
			jq '.tasks_failed = (.tasks_failed + 1)' "$agent_file" > "${agent_file}.tmp"
			mv "${agent_file}.tmp" "$agent_file"
		fi
	fi
	
	orch_release_lock "task_${task_id}"
	return 0
}

# Workflow: Submit a workflow with dependencies
orch_submit_workflow() {
	local workflow_name="$1"
	local workflow_tasks="$2"  # JSON array of task definitions with dependencies
	
	local workflow_id
	workflow_id=$(orch_generate_id "workflow")
	local workflow_file="${ORCH_STATE_DIR}/workflow_${workflow_id}.json"
	
	# Acquire lock
	if ! orch_acquire_lock "workflow_${workflow_id}"; then
		return 1
	fi
	
	# Create workflow file
	cat > "$workflow_file" <<-EOF
	{
	  "workflow_id": "$workflow_id",
	  "workflow_name": "$workflow_name",
	  "status": "running",
	  "tasks": $workflow_tasks,
	  "submitted_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
	  "completed_tasks": [],
	  "failed_tasks": []
	}
	EOF
	
	orch_release_lock "workflow_${workflow_id}"
	
	orch_log "INFO" "Workflow submitted: $workflow_id ($workflow_name)"
	echo "$workflow_id"
	return 0
}

# Get workflow status
orch_get_workflow_status() {
	local workflow_id="$1"
	local workflow_file="${ORCH_STATE_DIR}/workflow_${workflow_id}.json"
	
	if [ ! -f "$workflow_file" ]; then
		orch_log "ERROR" "Workflow not found: $workflow_id"
		return 1
	fi
	
	cat "$workflow_file"
	return 0
}

# Aggregate results from multiple tasks
orch_aggregate_results() {
	local task_ids="$*"
	local aggregated_file="${ORCH_RESULTS_DIR}/aggregated_$(date +%s%N).json"
	
	echo "{" > "$aggregated_file"
	echo '  "aggregation_timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",' >> "$aggregated_file"
	echo '  "results": [' >> "$aggregated_file"
	
	local first=true
	for task_id in $task_ids; do
		local result_file="${ORCH_RESULTS_DIR}/${task_id}_result.json"
		if [ -f "$result_file" ]; then
			if [ "$first" = true ]; then
				first=false
			else
				echo "    ," >> "$aggregated_file"
			fi
			cat "$result_file" >> "$aggregated_file"
		fi
	done
	
	echo '  ]' >> "$aggregated_file"
	echo '}' >> "$aggregated_file"
	
	orch_log "INFO" "Results aggregated: $aggregated_file"
	echo "$aggregated_file"
	return 0
}

# Cleanup old completed/failed tasks
orch_cleanup_old_tasks() {
	local days_old="${1:-7}"
	local count=0
	
	orch_log "INFO" "Cleaning up tasks older than $days_old days"
	
	# Find and remove old completed tasks
	find "${ORCH_TASKS_DIR}" -name "*.completed" -mtime "+${days_old}" -type f -delete 2>/dev/null && count=$((count + 1)) || true
	find "${ORCH_TASKS_DIR}" -name "*.failed" -mtime "+${days_old}" -type f -delete 2>/dev/null && count=$((count + 1)) || true
	
	orch_log "INFO" "Cleaned up $count old task files"
	return 0
}

# Export functions for use in other scripts
export -f orch_log orch_acquire_lock orch_release_lock orch_generate_id
export -f orch_register_agent orch_deregister_agent orch_agent_heartbeat orch_list_agents
export -f orch_submit_task orch_assign_task orch_get_next_task orch_complete_task orch_fail_task
export -f orch_submit_workflow orch_get_workflow_status orch_aggregate_results orch_cleanup_old_tasks
