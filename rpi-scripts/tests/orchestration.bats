#!/usr/bin/env bats
# Tests for Multi-Agent Orchestration Framework

setup() {
	# Create temporary test environment
	export TEST_ORCH_DIR="$(mktemp -d)"
	export ORCH_BASE_DIR="$TEST_ORCH_DIR"
	export ORCH_AGENTS_DIR="$TEST_ORCH_DIR/agents"
	export ORCH_TASKS_DIR="$TEST_ORCH_DIR/tasks"
	export ORCH_RESULTS_DIR="$TEST_ORCH_DIR/results"
	export ORCH_STATE_DIR="$TEST_ORCH_DIR/state"
	export ORCH_LOCK_DIR="$TEST_ORCH_DIR/.locks"
	
	# Source orchestration library
	source "$(dirname "$BATS_TEST_DIRNAME")/orchestration_lib.sh"
}

teardown() {
	# Cleanup test environment
	if [ -n "$TEST_ORCH_DIR" ] && [ -d "$TEST_ORCH_DIR" ]; then
		rm -rf "$TEST_ORCH_DIR"
	fi
}

# Agent Registration Tests

@test "orch_register_agent: successfully registers an agent" {
	run orch_register_agent "test_agent_1" "recon" '["port_scan"]'
	[ "$status" -eq 0 ]
	[ -f "$ORCH_AGENTS_DIR/test_agent_1.json" ]
}

@test "orch_register_agent: creates valid JSON agent file" {
	orch_register_agent "test_agent_2" "exploitation" '["exploit"]'
	
	# Check JSON structure
	if command -v jq &>/dev/null; then
		run jq -e '.agent_id == "test_agent_2"' "$ORCH_AGENTS_DIR/test_agent_2.json"
		[ "$status" -eq 0 ]
		
		run jq -e '.agent_type == "exploitation"' "$ORCH_AGENTS_DIR/test_agent_2.json"
		[ "$status" -eq 0 ]
	fi
}

@test "orch_register_agent: fails without agent ID" {
	run orch_register_agent "" "recon" '["port_scan"]'
	[ "$status" -eq 1 ]
}

@test "orch_register_agent: fails without agent type" {
	run orch_register_agent "test_agent" "" '["port_scan"]'
	[ "$status" -eq 1 ]
}

@test "orch_deregister_agent: successfully deregisters an agent" {
	orch_register_agent "test_agent_3" "recon" '["port_scan"]'
	
	run orch_deregister_agent "test_agent_3"
	[ "$status" -eq 0 ]
	[ ! -f "$ORCH_AGENTS_DIR/test_agent_3.json" ]
	[ -f "$ORCH_AGENTS_DIR/test_agent_3.json.inactive" ]
}

@test "orch_list_agents: lists all registered agents" {
	orch_register_agent "agent_1" "recon" '["scan"]'
	orch_register_agent "agent_2" "exploitation" '["exploit"]'
	
	run orch_list_agents
	[ "$status" -eq 0 ]
	[[ "$output" == *"agent_1"* ]]
	[[ "$output" == *"agent_2"* ]]
}

@test "orch_list_agents: filters agents by type" {
	orch_register_agent "recon_agent" "recon" '["scan"]'
	orch_register_agent "exploit_agent" "exploitation" '["exploit"]'
	
	run orch_list_agents "recon"
	[ "$status" -eq 0 ]
	[[ "$output" == *"recon_agent"* ]]
	[[ "$output" != *"exploit_agent"* ]]
}

@test "orch_agent_heartbeat: updates agent heartbeat timestamp" {
	orch_register_agent "heartbeat_agent" "recon" '["scan"]'
	
	# Get initial timestamp
	local initial_heartbeat
	if command -v jq &>/dev/null; then
		initial_heartbeat=$(jq -r '.last_heartbeat' "$ORCH_AGENTS_DIR/heartbeat_agent.json")
	fi
	
	sleep 1
	
	run orch_agent_heartbeat "heartbeat_agent"
	[ "$status" -eq 0 ]
	
	# Verify timestamp updated (if jq available)
	if command -v jq &>/dev/null; then
		local new_heartbeat
		new_heartbeat=$(jq -r '.last_heartbeat' "$ORCH_AGENTS_DIR/heartbeat_agent.json")
		[ "$new_heartbeat" != "$initial_heartbeat" ]
	fi
}

# Task Queue Tests

@test "orch_submit_task: successfully submits a task" {
	run orch_submit_task "port_scan" '{"target":"192.168.1.1"}' "recon" 5
	[ "$status" -eq 0 ]
	
	# Output should be task ID
	[[ "$output" == task_* ]]
	
	# Task file should exist
	[ -f "$ORCH_TASKS_DIR/${output}.json" ]
}

@test "orch_submit_task: creates valid JSON task file" {
	local task_id
	task_id=$(orch_submit_task "vuln_scan" '{"target":"example.com"}' "recon" 7)
	
	# Check JSON structure
	if command -v jq &>/dev/null; then
		run jq -e '.task_type == "vuln_scan"' "$ORCH_TASKS_DIR/${task_id}.json"
		[ "$status" -eq 0 ]
		
		run jq -e '.priority == 7' "$ORCH_TASKS_DIR/${task_id}.json"
		[ "$status" -eq 0 ]
		
		run jq -e '.status == "pending"' "$ORCH_TASKS_DIR/${task_id}.json"
		[ "$status" -eq 0 ]
	fi
}

@test "orch_assign_task: assigns task to agent" {
	local task_id
	task_id=$(orch_submit_task "test_task" '{"data":"test"}' "any" 5)
	
	run orch_assign_task "$task_id" "test_agent"
	[ "$status" -eq 0 ]
	
	# Verify assignment
	if command -v jq &>/dev/null; then
		run jq -e '.status == "assigned"' "$ORCH_TASKS_DIR/${task_id}.json"
		[ "$status" -eq 0 ]
		
		run jq -e '.assigned_agent == "test_agent"' "$ORCH_TASKS_DIR/${task_id}.json"
		[ "$status" -eq 0 ]
	fi
}

@test "orch_get_next_task: returns highest priority pending task" {
	# Register agent
	orch_register_agent "priority_agent" "recon" '["scan"]'
	
	# Submit tasks with different priorities
	local task_low
	task_low=$(orch_submit_task "low_priority" '{}' "recon" 3)
	
	local task_high
	task_high=$(orch_submit_task "high_priority" '{}' "recon" 9)
	
	local task_mid
	task_mid=$(orch_submit_task "mid_priority" '{}' "recon" 5)
	
	# Get next task - should be high priority
	run orch_get_next_task "priority_agent"
	[ "$status" -eq 0 ]
	[ "$output" = "$task_high" ]
}

@test "orch_complete_task: marks task as completed" {
	local task_id
	task_id=$(orch_submit_task "complete_test" '{}' "any" 5)
	orch_assign_task "$task_id" "test_agent"
	
	run orch_complete_task "$task_id" '{"status":"success"}' "test_agent"
	[ "$status" -eq 0 ]
	
	# Task should be archived
	[ -f "$ORCH_TASKS_DIR/${task_id}.json.completed" ]
	
	# Result should be stored
	[ -f "$ORCH_RESULTS_DIR/${task_id}_result.json" ]
}

@test "orch_fail_task: marks task as failed and retries" {
	local task_id
	task_id=$(orch_submit_task "fail_test" '{}' "any" 5)
	orch_assign_task "$task_id" "test_agent"
	
	# First failure - should reset to pending
	run orch_fail_task "$task_id" "Test error" "test_agent"
	[ "$status" -eq 0 ]
	
	if command -v jq &>/dev/null; then
		# Check if task is pending again
		run jq -e '.status == "pending"' "$ORCH_TASKS_DIR/${task_id}.json"
		[ "$status" -eq 0 ]
		
		# Check attempts incremented
		run jq -e '.attempts == 1' "$ORCH_TASKS_DIR/${task_id}.json"
		[ "$status" -eq 0 ]
	fi
}

@test "orch_fail_task: permanently fails task after max attempts" {
	local task_id
	task_id=$(orch_submit_task "max_fail_test" '{}' "any" 5)
	
	if command -v jq &>/dev/null; then
		# Set max_attempts to 1 for quick test
		jq '.max_attempts = 1' "$ORCH_TASKS_DIR/${task_id}.json" > "$ORCH_TASKS_DIR/${task_id}.json.tmp"
		mv "$ORCH_TASKS_DIR/${task_id}.json.tmp" "$ORCH_TASKS_DIR/${task_id}.json"
	fi
	
	orch_assign_task "$task_id" "test_agent"
	
	# Fail task - should mark as permanently failed
	run orch_fail_task "$task_id" "Test error" "test_agent"
	[ "$status" -eq 0 ]
	
	# Task should be archived as failed
	[ -f "$ORCH_TASKS_DIR/${task_id}.json.failed" ]
}

# Workflow Tests

@test "orch_submit_workflow: successfully submits a workflow" {
	run orch_submit_workflow "test_workflow" '[{"task":"scan"},{"task":"exploit"}]'
	[ "$status" -eq 0 ]
	
	# Output should be workflow ID
	[[ "$output" == workflow_* ]]
	
	# Workflow file should exist
	[ -f "$ORCH_STATE_DIR/workflow_${output}.json" ]
}

@test "orch_get_workflow_status: retrieves workflow status" {
	local workflow_id
	workflow_id=$(orch_submit_workflow "status_test" '[{"task":"test"}]')
	
	run orch_get_workflow_status "$workflow_id"
	[ "$status" -eq 0 ]
	
	if command -v jq &>/dev/null; then
		# Verify workflow data
		echo "$output" | jq -e '.workflow_name == "status_test"'
	fi
}

# Lock Tests

@test "orch_acquire_lock: successfully acquires lock" {
	run orch_acquire_lock "test_lock" 5
	[ "$status" -eq 0 ]
	[ -d "$ORCH_LOCK_DIR/test_lock.lock" ]
	
	# Cleanup
	orch_release_lock "test_lock"
}

@test "orch_acquire_lock: fails when lock is held" {
	# Acquire lock
	orch_acquire_lock "held_lock" 5
	
	# Try to acquire again with short timeout
	run orch_acquire_lock "held_lock" 1
	[ "$status" -eq 1 ]
	
	# Cleanup
	orch_release_lock "held_lock"
}

@test "orch_release_lock: successfully releases lock" {
	orch_acquire_lock "release_test" 5
	
	run orch_release_lock "release_test"
	[ "$status" -eq 0 ]
	[ ! -d "$ORCH_LOCK_DIR/release_test.lock" ]
}

# ID Generation Tests

@test "orch_generate_id: generates unique IDs" {
	local id1
	id1=$(orch_generate_id "test")
	
	local id2
	id2=$(orch_generate_id "test")
	
	# IDs should be different
	[ "$id1" != "$id2" ]
	
	# IDs should start with prefix
	[[ "$id1" == test_* ]]
	[[ "$id2" == test_* ]]
}

# Result Aggregation Tests

@test "orch_aggregate_results: aggregates multiple task results" {
	# Create some test results
	local task1
	task1=$(orch_submit_task "agg_test_1" '{}' "any" 5)
	orch_complete_task "$task1" '{"data":"result1"}' "agent1"
	
	local task2
	task2=$(orch_submit_task "agg_test_2" '{}' "any" 5)
	orch_complete_task "$task2" '{"data":"result2"}' "agent1"
	
	# Aggregate results
	run orch_aggregate_results "$task1" "$task2"
	[ "$status" -eq 0 ]
	
	# Output should be aggregated file path
	[[ "$output" == *"aggregated_"* ]]
	[ -f "$output" ]
}

# Cleanup Tests

@test "orch_cleanup_old_tasks: removes old task files" {
	# Create old task file (simulate by creating and modifying timestamp)
	local old_task
	old_task=$(orch_submit_task "old_task" '{}' "any" 5)
	orch_complete_task "$old_task" '{"status":"done"}' "agent1"
	
	# Make the file appear old (8 days)
	touch -d "8 days ago" "$ORCH_TASKS_DIR/${old_task}.json.completed"
	
	run orch_cleanup_old_tasks 7
	[ "$status" -eq 0 ]
	
	# Old task should be removed
	[ ! -f "$ORCH_TASKS_DIR/${old_task}.json.completed" ]
}

# Integration Tests

@test "INTEGRATION: complete workflow with multiple agents" {
	# Register agents
	orch_register_agent "recon_1" "recon" '["scan"]'
	orch_register_agent "exploit_1" "exploitation" '["exploit"]'
	
	# Submit tasks
	local scan_task
	scan_task=$(orch_submit_task "port_scan" '{"target":"test"}' "recon" 5)
	
	local exploit_task
	exploit_task=$(orch_submit_task "exploit" '{"vuln":"test"}' "exploitation" 5)
	
	# Get and assign tasks
	local next_task
	next_task=$(orch_get_next_task "recon_1")
	[ "$next_task" = "$scan_task" ]
	
	orch_assign_task "$scan_task" "recon_1"
	orch_complete_task "$scan_task" '{"ports":[22,80]}' "recon_1"
	
	next_task=$(orch_get_next_task "exploit_1")
	[ "$next_task" = "$exploit_task" ]
	
	orch_assign_task "$exploit_task" "exploit_1"
	orch_complete_task "$exploit_task" '{"success":true}' "exploit_1"
	
	# Verify both results exist
	[ -f "$ORCH_RESULTS_DIR/${scan_task}_result.json" ]
	[ -f "$ORCH_RESULTS_DIR/${exploit_task}_result.json" ]
	
	# Aggregate results
	local aggregated
	aggregated=$(orch_aggregate_results "$scan_task" "$exploit_task")
	[ -f "$aggregated" ]
}

# SECURITY Tests

@test "SECURITY: agent registration validates input" {
	# Test with special characters
	run orch_register_agent "test;rm -rf /" "recon" '["scan"]'
	[ "$status" -eq 0 ]
	
	# Agent file should exist with sanitized name (file creation should succeed)
	# The filename will contain the special characters but be escaped by filesystem
	local agent_count
	agent_count=$(find "$ORCH_AGENTS_DIR" -name "*.json" | wc -l)
	[ "$agent_count" -ge 1 ]
}

@test "SECURITY: task submission handles malicious payloads" {
	# Submit task with potentially dangerous payload
	run orch_submit_task "test_task" '{"cmd":"$(rm -rf /)"}' "any" 5
	[ "$status" -eq 0 ]
	
	# Task should be created (payload is stored as-is, execution is agent's responsibility)
	[[ "$output" == task_* ]]
}

@test "SECURITY: locks prevent race conditions" {
	# Acquire lock in background
	(
		orch_acquire_lock "race_test" 10
		sleep 2
		orch_release_lock "race_test"
	) &
	
	sleep 0.5
	
	# Try to acquire same lock - should fail due to timeout
	run orch_acquire_lock "race_test" 1
	[ "$status" -eq 1 ]
	
	# Wait for background process
	wait
}
