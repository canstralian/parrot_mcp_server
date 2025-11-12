#!/usr/bin/env bash
# orchestration_controller.sh - Multi-Agent Orchestration Controller
# Central coordinator for task distribution and agent management

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/orchestration_lib.sh"

# Controller configuration
CONTROLLER_ID="controller_$$"
CONTROLLER_INTERVAL="${CONTROLLER_INTERVAL:-2}"  # Check interval in seconds
CONTROLLER_RUNNING=true

# Trap signals for graceful shutdown
trap 'CONTROLLER_RUNNING=false' SIGTERM SIGINT

usage() {
	cat <<-EOF
		Usage: $0 [OPTIONS]
		
		Multi-Agent Orchestration Controller - Manages task distribution and agent health
		
		OPTIONS:
		  --interval SECONDS    Check interval for task distribution (default: 2)
		  --daemon              Run as background daemon
		  --stop                Stop running controller
		  --status              Show controller status
		  --help                Show this help message
		
		EXAMPLES:
		  $0                    Start controller in foreground
		  $0 --daemon           Start controller as daemon
		  $0 --stop             Stop running controller
		  $0 --status           Check if controller is running
	EOF
}

# Check if controller is already running
is_controller_running() {
	local pid_file="${ORCH_STATE_DIR}/controller.pid"
	
	if [ -f "$pid_file" ]; then
		local pid
		pid=$(cat "$pid_file")
		if kill -0 "$pid" 2>/dev/null; then
			return 0
		else
			# Stale PID file
			rm -f "$pid_file"
		fi
	fi
	return 1
}

# Stop running controller
stop_controller() {
	local pid_file="${ORCH_STATE_DIR}/controller.pid"
	
	if [ -f "$pid_file" ]; then
		local pid
		pid=$(cat "$pid_file")
		if kill -0 "$pid" 2>/dev/null; then
			orch_log "INFO" "Stopping controller (PID: $pid)"
			kill "$pid"
			sleep 1
			if kill -0 "$pid" 2>/dev/null; then
				kill -9 "$pid" 2>/dev/null || true
			fi
			rm -f "$pid_file"
			orch_log "INFO" "Controller stopped"
			return 0
		else
			rm -f "$pid_file"
		fi
	fi
	
	orch_log "WARN" "Controller not running"
	return 1
}

# Show controller status
show_status() {
	local pid_file="${ORCH_STATE_DIR}/controller.pid"
	
	if is_controller_running; then
		local pid
		pid=$(cat "$pid_file")
		echo "Controller is running (PID: $pid)"
		
		# Show statistics
		local agent_count
		agent_count=$(find "${ORCH_AGENTS_DIR}" -name "*.json" -type f 2>/dev/null | wc -l)
		echo "Active agents: $agent_count"
		
		local pending_tasks
		pending_tasks=$(grep -l '"status": "pending"' "${ORCH_TASKS_DIR}"/*.json 2>/dev/null | wc -l)
		echo "Pending tasks: $pending_tasks"
		
		local completed_tasks
		completed_tasks=$(find "${ORCH_TASKS_DIR}" -name "*.completed" -type f 2>/dev/null | wc -l)
		echo "Completed tasks: $completed_tasks"
		
		return 0
	else
		echo "Controller is not running"
		return 1
	fi
}

# Monitor agent health
monitor_agents() {
	local current_time
	current_time=$(date +%s)
	local timeout=60  # Agent timeout in seconds
	
	for agent_file in "${ORCH_AGENTS_DIR}"/*.json; do
		[ -f "$agent_file" ] || continue
		
		local agent_id
		agent_id=$(basename "$agent_file" .json)
		
		# Check last heartbeat
		local last_heartbeat
		if command -v jq &>/dev/null; then
			last_heartbeat=$(jq -r '.last_heartbeat' "$agent_file")
		else
			last_heartbeat=$(grep '"last_heartbeat"' "$agent_file" | cut -d'"' -f4)
		fi
		
		# Convert ISO timestamp to epoch (approximation for Bash)
		local heartbeat_epoch
		heartbeat_epoch=$(date -d "$last_heartbeat" +%s 2>/dev/null || echo "0")
		
		if [ "$heartbeat_epoch" -gt 0 ] && [ $((current_time - heartbeat_epoch)) -gt "$timeout" ]; then
			orch_log "WARN" "Agent timeout detected: $agent_id (last heartbeat: $last_heartbeat)"
			
			# Mark agent as inactive
			if command -v jq &>/dev/null; then
				jq '.status = "inactive"' "$agent_file" > "${agent_file}.tmp"
				mv "${agent_file}.tmp" "$agent_file"
			fi
			
			# Reassign any tasks assigned to this agent
			for task_file in "${ORCH_TASKS_DIR}"/*.json; do
				[ -f "$task_file" ] || continue
				
				if grep -q "\"assigned_agent\": \"$agent_id\"" "$task_file"; then
					local task_id
					task_id=$(basename "$task_file" .json)
					orch_log "INFO" "Reassigning task from inactive agent: $task_id"
					
					# Reset task to pending
					if command -v jq &>/dev/null; then
						jq '.status = "pending" | .assigned_agent = null' "$task_file" > "${task_file}.tmp"
						mv "${task_file}.tmp" "$task_file"
					fi
				fi
			done
		fi
	done
}

# Distribute tasks to agents
distribute_tasks() {
	# Get list of active agents
	local agents
	agents=$(orch_list_agents)
	
	if [ -z "$agents" ]; then
		return 0
	fi
	
	# Distribute pending tasks
	for task_file in "${ORCH_TASKS_DIR}"/*.json; do
		[ -f "$task_file" ] || continue
		
		# Check if task is pending
		if ! grep -q '"status": "pending"' "$task_file"; then
			continue
		fi
		
		local task_id
		task_id=$(basename "$task_file" .json)
		
		# Get task requirements
		local required_capability
		if command -v jq &>/dev/null; then
			required_capability=$(jq -r '.required_capability' "$task_file")
		else
			required_capability=$(grep '"required_capability"' "$task_file" | cut -d'"' -f4)
		fi
		
		# Find suitable agent
		for agent_id in $agents; do
			local agent_file="${ORCH_AGENTS_DIR}/${agent_id}.json"
			[ -f "$agent_file" ] || continue
			
			# Check agent status
			if ! grep -q '"status": "active"' "$agent_file"; then
				continue
			fi
			
			# Check capability match
			local agent_type
			if command -v jq &>/dev/null; then
				agent_type=$(jq -r '.agent_type' "$agent_file")
			else
				agent_type=$(grep '"agent_type"' "$agent_file" | cut -d'"' -f4)
			fi
			
			if [ "$required_capability" = "any" ] || [ "$required_capability" = "$agent_type" ]; then
				# Assign task to agent
				if orch_assign_task "$task_id" "$agent_id"; then
					orch_log "INFO" "Task distributed: $task_id -> $agent_id"
					break
				fi
			fi
		done
	done
}

# Main controller loop
run_controller() {
	local pid_file="${ORCH_STATE_DIR}/controller.pid"
	
	# Check if already running
	if is_controller_running; then
		orch_log "ERROR" "Controller already running"
		exit 1
	fi
	
	# Store PID
	echo $$ > "$pid_file"
	
	orch_log "INFO" "Orchestration controller started (PID: $$)"
	
	while [ "$CONTROLLER_RUNNING" = true ]; do
		# Monitor agent health
		monitor_agents
		
		# Distribute tasks
		distribute_tasks
		
		# Cleanup old tasks periodically (every 100 iterations)
		if [ $((RANDOM % 100)) -eq 0 ]; then
			orch_cleanup_old_tasks 7
		fi
		
		# Sleep before next iteration
		sleep "$CONTROLLER_INTERVAL"
	done
	
	# Cleanup on exit
	rm -f "$pid_file"
	orch_log "INFO" "Orchestration controller stopped"
}

# Parse arguments
DAEMON_MODE=false
ACTION="run"

while [[ $# -gt 0 ]]; do
	case "$1" in
		--interval)
			CONTROLLER_INTERVAL="$2"
			shift 2
			;;
		--daemon)
			DAEMON_MODE=true
			shift
			;;
		--stop)
			ACTION="stop"
			shift
			;;
		--status)
			ACTION="status"
			shift
			;;
		--help|-h)
			usage
			exit 0
			;;
		*)
			echo "Unknown option: $1"
			usage
			exit 1
			;;
	esac
done

# Execute action
case "$ACTION" in
	run)
		if [ "$DAEMON_MODE" = true ]; then
			orch_log "INFO" "Starting controller as daemon"
			nohup "$0" --interval "$CONTROLLER_INTERVAL" >> "${ORCH_STATE_DIR}/controller.log" 2>&1 &
			echo "Controller started as daemon (PID: $!)"
		else
			run_controller
		fi
		;;
	stop)
		stop_controller
		;;
	status)
		show_status
		;;
esac
