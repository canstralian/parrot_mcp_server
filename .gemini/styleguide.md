Gemini Code Review Style Guide

Project Context

This repository implements a Parrot MCP server for security automation workflows.

The system orchestrates tools to perform authorized security assessments against explicitly defined targets. Code should prioritize:
	•	safety
	•	deterministic execution
	•	auditability
	•	minimal operational impact
	•	reproducible runs

Security tooling must never expand scope automatically.

Gemini reviews should treat this as a security-sensitive automation system, not a general application.

⸻

Review Priorities

Gemini should prioritize findings in the following order:
	1.	Security
	2.	Scope enforcement
	3.	Input validation
	4.	Deterministic behavior
	5.	Logging and traceability
	6.	Maintainability
	7.	Efficiency

⸻

Scope Enforcement Rules

All security tools must operate only on user-provided targets.

Flag code if it:
	•	performs scanning against inferred hosts
	•	expands domains automatically
	•	enumerates third-party infrastructure
	•	uses wildcard or network-wide scanning

Preferred pattern:

validate_scope(target)
run_scan(target)

Disallowed pattern:

targets = discover_hosts(domain)
scan(targets)

Unless explicitly authorized by configuration.

⸻

Input Validation Requirements

Every external input must be validated before execution.

This includes:
	•	CLI parameters
	•	API input
	•	workflow parameters
	•	user prompts

Validation must include:
	•	hostname/IP validation
	•	parameter sanitization
	•	scope authorization
	•	required parameter presence

Gemini should flag any code executing commands without validation.

⸻

Command Execution Safety

Shell execution must be implemented using safe subprocess patterns.

Preferred:

subprocess.run(
    ["nmap", "-p", ports, target],
    check=True
)

Flag uses of:

os.system()
subprocess(shell=True)
string-form command execution


⸻

Logging Requirements

All tool execution must be logged.

Each run must produce:

/runs/<run_id>/
    commands.log
    artifacts/
    raw/
    summary.md

Log entries must include:
	•	timestamp
	•	tool name
	•	executed command
	•	artifact path

Gemini should flag code that executes tools without logging.

⸻

Deterministic Tool Invocation

Tools must be called with explicit parameters.

Flag patterns that rely on defaults or implicit behavior.

Bad:

run_nmap(target)

Preferred:

run_nmap(
    target=target,
    ports="80,443",
    timing="T3",
    output="scan.xml"
)


⸻

Low-Impact Security Testing

Default behavior should favor low-impact techniques.

Preferred sequence:
	1.	passive enumeration
	2.	metadata inspection
	3.	targeted probing
	4.	active scanning

Gemini should flag:
	•	aggressive scans as defaults
	•	high-intensity scanning profiles
	•	IDS-triggering commands without warnings

⸻

Risk Classification

Security tools should include a risk classification.

Accepted values:

SAFE
LOW_IMPACT
ACTIVE
DISRUPTIVE

Example metadata:

tool:
  name: http_probe
  risk: LOW_IMPACT

Gemini should suggest adding risk classification when missing.

⸻

Code Structure Guidelines

Functions should be:
	•	small
	•	single-purpose
	•	easily testable

Recommended length:

5–25 lines

Large functions should be decomposed.

⸻

Naming Conventions

Use descriptive names reflecting the workflow step.

Preferred:

validate_scope
collect_http_headers
run_passive_dns
enumerate_subdomains

Avoid generic names:

process_data
helper
do_scan


⸻

Workflow Architecture

Security workflows should follow a predictable pipeline:

validate_scope
→ passive_enumeration
→ service_identification
→ targeted_probing
→ reporting

Gemini should suggest decomposing monolithic scripts into workflow stages.

⸻

Secrets and Credentials

Sensitive values must never be committed.

Flag:
	•	API keys
	•	tokens
	•	passwords
	•	private keys

Preferred storage:

environment variables
.env files (ignored by git)
secret managers


⸻

Result Reuse

Before executing tools, code should check whether previous results exist.

Preferred pattern:

if artifact_exists(run_id, "dns_enum"):
    reuse_results()
else:
    run_dns_enum()

Gemini should recommend result reuse when workflows repeatedly execute the same tools.

⸻

Documentation Requirements

Every tool should include documentation covering:
	•	description
	•	parameters
	•	risk level
	•	example usage

Example:

Tool: http_header_probe

Description:
Retrieve HTTP headers from a target host.

Risk:
LOW_IMPACT

Parameters:
target
port


⸻

What Gemini Should Avoid Suggesting

Gemini should avoid recommending:
	•	scanning entire networks
	•	aggressive fuzzing by default
	•	automated exploitation
	•	privilege escalation attempts
	•	destructive testing techniques

Unless explicitly requested by workflow configuration.

⸻

Design Philosophy

This project treats security automation as instrumentation, not opportunistic hacking.

Key principles:
	•	explicit scope
	•	minimal risk
	•	deterministic workflows
	•	traceable execution
	•	reproducible results

Gemini code reviews should reinforce these principles.

⸻