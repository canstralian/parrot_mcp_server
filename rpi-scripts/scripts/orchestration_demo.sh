#!/usr/bin/env bash
# orchestration_demo.sh - Demo script for Multi-Agent Orchestration Framework
# Shows how to use the orchestration system with multiple agents and tasks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "${SCRIPT_DIR}/orchestration_lib.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_demo() {
	echo -e "${BLUE}[DEMO]${NC} $*"
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $*"
}

log_info() {
	echo -e "${YELLOW}[INFO]${NC} $*"
}

# Demo function: Start the orchestration system
demo_start_system() {
	log_demo "Starting Multi-Agent Orchestration System"
	echo ""
	
	# Start controller in background
	log_info "Starting orchestration controller..."
	"${SCRIPT_DIR}/scripts/orchestration_controller.sh" --daemon
	sleep 2
	
	# Check controller status
	if "${SCRIPT_DIR}/scripts/orchestration_controller.sh" --status > /dev/null 2>&1; then
		log_success "Controller started successfully"
	else
		log_error "Failed to start controller"
		return 1
	fi
	
	echo ""
}

# Demo function: Start agents
demo_start_agents() {
	log_demo "Starting Multiple Specialized Agents"
	echo ""
	
	# Start recon agents
	log_info "Starting 2 reconnaissance agents..."
	"${SCRIPT_DIR}/scripts/orchestration_agent.sh" --type recon --id "recon_agent_1" --daemon
	"${SCRIPT_DIR}/scripts/orchestration_agent.sh" --type recon --id "recon_agent_2" --daemon
	sleep 1
	
	# Start exploitation agent
	log_info "Starting 1 exploitation agent..."
	"${SCRIPT_DIR}/scripts/orchestration_agent.sh" --type exploitation --id "exploit_agent_1" --daemon
	sleep 1
	
	# Start reporting agent
	log_info "Starting 1 reporting agent..."
	"${SCRIPT_DIR}/scripts/orchestration_agent.sh" --type reporting --id "report_agent_1" --daemon
	sleep 2
	
	# Show agent status
	log_success "Agents started successfully"
	echo ""
	"${SCRIPT_DIR}/scripts/orchestration_cli.sh" agents status
	echo ""
}

# Demo function: Submit tasks
demo_submit_tasks() {
	log_demo "Submitting Various Tasks to the Queue"
	echo ""
	
	# Submit recon tasks
	log_info "Submitting reconnaissance tasks..."
	local task1
	task1=$("${SCRIPT_DIR}/scripts/orchestration_cli.sh" tasks submit port_scan '{"target":"192.168.1.1"}' recon 9)
	echo "  - Port scan task: $task1"
	
	local task2
	task2=$("${SCRIPT_DIR}/scripts/orchestration_cli.sh" tasks submit service_detection '{"target":"192.168.1.1"}' recon 8)
	echo "  - Service detection task: $task2"
	
	local task3
	task3=$("${SCRIPT_DIR}/scripts/orchestration_cli.sh" tasks submit vulnerability_scan '{"target":"192.168.1.1"}' recon 7)
	echo "  - Vulnerability scan task: $task3"
	
	# Submit exploitation task
	log_info "Submitting exploitation task..."
	local task4
	task4=$("${SCRIPT_DIR}/scripts/orchestration_cli.sh" tasks submit exploit_execution '{"vuln":"CVE-2024-1234"}' exploitation 8)
	echo "  - Exploit execution task: $task4"
	
	# Submit reporting task
	log_info "Submitting reporting task..."
	local task5
	task5=$("${SCRIPT_DIR}/scripts/orchestration_cli.sh" tasks submit report_generation '{"format":"pdf"}' reporting 6)
	echo "  - Report generation task: $task5"
	
	log_success "5 tasks submitted successfully"
	echo ""
	
	# Store task IDs for later
	export DEMO_TASK1="$task1"
	export DEMO_TASK2="$task2"
	export DEMO_TASK3="$task3"
	export DEMO_TASK4="$task4"
	export DEMO_TASK5="$task5"
}

# Demo function: Monitor task execution
demo_monitor_execution() {
	log_demo "Monitoring Task Execution (10 seconds)"
	echo ""
	
	local count=0
	while [ $count -lt 10 ]; do
		# Show system stats
		log_info "System status (iteration $((count + 1))/10):"
		"${SCRIPT_DIR}/scripts/orchestration_cli.sh" system stats
		echo ""
		
		sleep 1
		count=$((count + 1))
	done
	
	log_success "Monitoring complete"
	echo ""
}

# Demo function: Show results
demo_show_results() {
	log_demo "Displaying Task Results"
	echo ""
	
	# Check if tasks completed
	for task_id in "$DEMO_TASK1" "$DEMO_TASK2" "$DEMO_TASK3" "$DEMO_TASK4" "$DEMO_TASK5"; do
		local result_file="${ORCH_RESULTS_DIR}/${task_id}_result.json"
		
		if [ -f "$result_file" ]; then
			log_success "Task $task_id completed"
			if command -v jq &>/dev/null; then
				jq -C '.' "$result_file" | head -10
			else
				head -10 "$result_file"
			fi
			echo ""
		else
			log_info "Task $task_id still pending or failed"
		fi
	done
}

# Demo function: Aggregate results
demo_aggregate_results() {
	log_demo "Aggregating Results from Multiple Tasks"
	echo ""
	
	# Get completed task IDs
	local completed_tasks=""
	for task_id in "$DEMO_TASK1" "$DEMO_TASK2" "$DEMO_TASK3" "$DEMO_TASK4" "$DEMO_TASK5"; do
		if [ -f "${ORCH_RESULTS_DIR}/${task_id}_result.json" ]; then
			completed_tasks="$completed_tasks $task_id"
		fi
	done
	
	if [ -n "$completed_tasks" ]; then
		log_info "Aggregating results from: $completed_tasks"
		# shellcheck disable=SC2086
		local aggregated
		aggregated=$("${SCRIPT_DIR}/scripts/orchestration_cli.sh" results aggregate $completed_tasks)
		
		log_success "Results aggregated to: $aggregated"
		echo ""
		
		if command -v jq &>/dev/null; then
			jq -C '.' "$aggregated" | head -20
		else
			head -20 "$aggregated"
		fi
	else
		log_error "No completed tasks to aggregate"
	fi
	
	echo ""
}

# Demo function: Submit and monitor workflow
demo_workflow() {
	log_demo "Submitting and Monitoring Workflow"
	echo ""
	
	# Submit workflow
	log_info "Submitting security audit workflow..."
	local workflow_id
	workflow_id=$("${SCRIPT_DIR}/scripts/orchestration_cli.sh" workflows submit "security_audit" '[
		{"task_type":"port_scan","payload":{"target":"10.0.0.1"}},
		{"task_type":"service_detection","payload":{"target":"10.0.0.1"}},
		{"task_type":"vulnerability_scan","payload":{"target":"10.0.0.1"}},
		{"task_type":"report_generation","payload":{"format":"html"}}
	]')
	
	log_success "Workflow submitted: $workflow_id"
	echo ""
	
	# Show workflow status
	log_info "Workflow status:"
	"${SCRIPT_DIR}/scripts/orchestration_cli.sh" workflows status "$workflow_id"
	echo ""
}

# Demo function: Stop system
demo_stop_system() {
	log_demo "Stopping Multi-Agent Orchestration System"
	echo ""
	
	# Stop agents (kill all agent processes)
	log_info "Stopping agents..."
	pkill -f "orchestration_agent.sh" || true
	sleep 1
	
	# Stop controller
	log_info "Stopping controller..."
	"${SCRIPT_DIR}/scripts/orchestration_controller.sh" --stop || true
	sleep 1
	
	log_success "System stopped"
	echo ""
}

# Demo function: Cleanup
demo_cleanup() {
	log_demo "Cleaning Up Demo Data"
	echo ""
	
	log_info "Removing demo data..."
	rm -rf "${ORCH_AGENTS_DIR:?}"/*.json
	rm -rf "${ORCH_TASKS_DIR:?}"/*.json
	rm -rf "${ORCH_TASKS_DIR:?}"/*.completed
	rm -rf "${ORCH_TASKS_DIR:?}"/*.failed
	rm -rf "${ORCH_RESULTS_DIR:?}"/*.json
	rm -rf "${ORCH_STATE_DIR:?}"/workflow_*.json
	rm -rf "${ORCH_STATE_DIR:?}"/*.log
	
	log_success "Cleanup complete"
	echo ""
}

# Main demo function
main() {
	echo ""
	echo "=========================================="
	echo "  Multi-Agent Orchestration Demo"
	echo "=========================================="
	echo ""
	
	# Trap to ensure cleanup on exit
	trap 'demo_stop_system; demo_cleanup' EXIT INT TERM
	
	# Run demo steps
	demo_start_system
	demo_start_agents
	demo_submit_tasks
	demo_monitor_execution
	demo_show_results
	demo_aggregate_results
	demo_workflow
	
	echo ""
	log_demo "Demo Complete!"
	echo ""
	log_info "The orchestration system is now running in the background."
	log_info "You can interact with it using the CLI:"
	echo ""
	echo "  ${SCRIPT_DIR}/scripts/orchestration_cli.sh agents list"
	echo "  ${SCRIPT_DIR}/scripts/orchestration_cli.sh tasks list"
	echo "  ${SCRIPT_DIR}/scripts/orchestration_cli.sh system stats"
	echo ""
	log_info "To stop the system, run:"
	echo ""
	echo "  ${SCRIPT_DIR}/scripts/orchestration_controller.sh --stop"
	echo "  pkill -f orchestration_agent.sh"
	echo ""
	
	# Ask user if they want to keep system running
	if [ -t 0 ]; then
		read -r -p "Press Enter to stop the system and cleanup, or Ctrl+C to keep running... " _
	else
		log_info "Non-interactive mode - stopping system"
		sleep 2
	fi
}

main "$@"
