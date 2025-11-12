#!/usr/bin/env bash
# orchestration_agent.sh - Multi-Agent Worker
# Generic agent that processes tasks based on its type and capabilities

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/orchestration_lib.sh"

# Agent configuration
AGENT_TYPE="${AGENT_TYPE:-generic}"
AGENT_ID="${AGENT_ID:-agent_${AGENT_TYPE}_$$}"
AGENT_RUNNING=true
POLL_INTERVAL="${POLL_INTERVAL:-3}"  # Task polling interval in seconds

# Trap signals for graceful shutdown
trap 'AGENT_RUNNING=false' SIGTERM SIGINT

usage() {
	cat <<-EOF
		Usage: $0 [OPTIONS]
		
		Multi-Agent Worker - Processes tasks from orchestration queue
		
		OPTIONS:
		  --type TYPE           Agent type: recon|exploitation|reporting|generic (default: generic)
		  --id ID               Custom agent ID (default: auto-generated)
		  --interval SECONDS    Task polling interval (default: 3)
		  --daemon              Run as background daemon
		  --help                Show this help message
		
		EXAMPLES:
		  $0 --type recon                    Start reconnaissance agent
		  $0 --type exploitation --daemon    Start exploitation agent as daemon
		  $0 --type reporting                Start reporting agent
	EOF
}

# Register agent capabilities based on type
get_capabilities() {
	local type="$1"
	
	case "$type" in
		recon)
			echo '["port_scan", "service_detection", "vulnerability_scan", "network_discovery"]'
			;;
		exploitation)
			echo '["exploit_execution", "payload_delivery", "privilege_escalation", "lateral_movement"]'
			;;
		reporting)
			echo '["result_aggregation", "report_generation", "data_analysis", "visualization"]'
			;;
		generic)
			echo '["general_task", "data_processing", "utility"]'
			;;
		*)
			echo '["unknown"]'
			;;
	esac
}

# Process a task based on agent type
process_task() {
	local task_id="$1"
	local task_file="${ORCH_TASKS_DIR}/${task_id}.json"
	
	if [ ! -f "$task_file" ]; then
		orch_log "ERROR" "Task file not found: $task_id"
		return 1
	fi
	
	# Get task details
	local task_type
	local task_payload
	if command -v jq &>/dev/null; then
		task_type=$(jq -r '.task_type' "$task_file")
		task_payload=$(jq -r '.payload' "$task_file")
	else
		task_type=$(grep '"task_type"' "$task_file" | cut -d'"' -f4)
		task_payload=$(grep '"payload"' "$task_file" | cut -d':' -f2- | sed 's/,$//')
	fi
	
	orch_log "INFO" "Processing task: $task_id (type: $task_type)"
	
	# Simulate task processing based on agent type
	local result
	case "$AGENT_TYPE" in
		recon)
			result=$(process_recon_task "$task_type" "$task_payload")
			;;
		exploitation)
			result=$(process_exploitation_task "$task_type" "$task_payload")
			;;
		reporting)
			result=$(process_reporting_task "$task_type" "$task_payload")
			;;
		generic)
			result=$(process_generic_task "$task_type" "$task_payload")
			;;
		*)
			orch_log "ERROR" "Unknown agent type: $AGENT_TYPE"
			return 1
			;;
	esac
	
	if [ $? -eq 0 ]; then
		# Task completed successfully
		orch_complete_task "$task_id" "$result" "$AGENT_ID"
		return 0
	else
		# Task failed
		orch_fail_task "$task_id" "Task processing failed" "$AGENT_ID"
		return 1
	fi
}

# Process reconnaissance tasks
process_recon_task() {
	local task_type="$1"
	local payload="$2"
	
	orch_log "INFO" "Recon task: $task_type"
	
	# Simulate processing time
	sleep 1
	
	case "$task_type" in
		port_scan)
			echo '{"status": "success", "ports_found": ["22", "80", "443"], "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		service_detection)
			echo '{"status": "success", "services": [{"port": "22", "service": "ssh"}, {"port": "80", "service": "http"}], "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		vulnerability_scan)
			echo '{"status": "success", "vulnerabilities": [{"cve": "CVE-2024-1234", "severity": "high"}], "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		*)
			echo '{"status": "success", "message": "Recon task completed", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
	esac
	
	return 0
}

# Process exploitation tasks
process_exploitation_task() {
	local task_type="$1"
	local payload="$2"
	
	orch_log "INFO" "Exploitation task: $task_type"
	
	# Simulate processing time
	sleep 2
	
	case "$task_type" in
		exploit_execution)
			echo '{"status": "success", "exploit_result": "shell_obtained", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		payload_delivery)
			echo '{"status": "success", "payload_delivered": true, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		privilege_escalation)
			echo '{"status": "success", "escalation": "root_access", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		*)
			echo '{"status": "success", "message": "Exploitation task completed", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
	esac
	
	return 0
}

# Process reporting tasks
process_reporting_task() {
	local task_type="$1"
	local payload="$2"
	
	orch_log "INFO" "Reporting task: $task_type"
	
	# Simulate processing time
	sleep 1
	
	case "$task_type" in
		result_aggregation)
			echo '{"status": "success", "aggregated_count": 5, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		report_generation)
			echo '{"status": "success", "report_file": "/tmp/report_'$(date +%s)'.pdf", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		data_analysis)
			echo '{"status": "success", "insights": ["high_risk_services", "outdated_software"], "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
		*)
			echo '{"status": "success", "message": "Reporting task completed", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
			;;
	esac
	
	return 0
}

# Process generic tasks
process_generic_task() {
	local task_type="$1"
	local payload="$2"
	
	orch_log "INFO" "Generic task: $task_type"
	
	# Simulate processing time
	sleep 1
	
	echo '{"status": "success", "message": "Task processed", "task_type": "'$task_type'", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'
	return 0
}

# Main agent loop
run_agent() {
	# Register agent
	local capabilities
	capabilities=$(get_capabilities "$AGENT_TYPE")
	
	if ! orch_register_agent "$AGENT_ID" "$AGENT_TYPE" "$capabilities"; then
		orch_log "ERROR" "Failed to register agent: $AGENT_ID"
		exit 1
	fi
	
	orch_log "INFO" "Agent started: $AGENT_ID (type: $AGENT_TYPE)"
	
	# Main processing loop
	while [ "$AGENT_RUNNING" = true ]; do
		# Send heartbeat
		orch_agent_heartbeat "$AGENT_ID"
		
		# Get next task
		local task_id
		if task_id=$(orch_get_next_task "$AGENT_ID"); then
			# Assign task to this agent
			if orch_assign_task "$task_id" "$AGENT_ID"; then
				# Process the task
				process_task "$task_id" || true
			fi
		fi
		
		# Sleep before next poll
		sleep "$POLL_INTERVAL"
	done
	
	# Deregister agent on exit
	orch_deregister_agent "$AGENT_ID"
	orch_log "INFO" "Agent stopped: $AGENT_ID"
}

# Parse arguments
DAEMON_MODE=false

while [[ $# -gt 0 ]]; do
	case "$1" in
		--type)
			AGENT_TYPE="$2"
			shift 2
			;;
		--id)
			AGENT_ID="$2"
			shift 2
			;;
		--interval)
			POLL_INTERVAL="$2"
			shift 2
			;;
		--daemon)
			DAEMON_MODE=true
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

# Run agent
if [ "$DAEMON_MODE" = true ]; then
	orch_log "INFO" "Starting agent as daemon: $AGENT_ID"
	nohup "$0" --type "$AGENT_TYPE" --id "$AGENT_ID" --interval "$POLL_INTERVAL" >> "${ORCH_STATE_DIR}/agent_${AGENT_ID}.log" 2>&1 &
	echo "Agent started as daemon (PID: $!)"
else
	run_agent
fi
