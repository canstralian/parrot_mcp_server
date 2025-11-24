
⸻

# Contributor’s Guide

Contributing to Parrot MCP Server isn’t a ritual—it’s a collaboration between many minds building a shared nervous system. This guide helps you integrate your work smoothly into the architecture.

### Getting Started
	1.	Fork the Repository
### Create your own working branch for features, bug fixes, or experiments.
	2.	Install Dependencies
### Follow the setup instructions in the project’s main documentation.
The server should run locally with a single command.
	3.	Understand the Flow
### Before writing code, trace how your feature interacts with:
	•	the Signal Reactor
	•	the Configuration Bus
	•	the Security Core
	•	the Plugin Modules
	•	the Observability Bus
Contributions that align with these pathways merge cleanly and extend the system instead of distorting it.

⸻

## Contribution Types

1. Feature Expansion

New capabilities should be written as modules where possible. Treat modules like “skills” the system can pick up without rewiring its brain.

2. Bug Fixes

Provide a clear, reproducible test case.
A failing test is the most honest piece of documentation you can give.

3. Documentation Improvements

Anything from README clarifications to architectural sketches is welcome. Good docs reduce cognitive load for every future contributor.

4. Performance Enhancements

Profile before optimizing.
Observability is your compass; don’t chase phantom speed.

⸻

## Coding Standards
	•	Keep functions short and composable.
	•	Follow existing naming conventions.
	•	Prefer immutability where practical.
	•	Keep behavior predictable—side effects should be explicit.
	•	Always include tests. A feature without tests is a rumor.

⸻

Testing & Validation
	1.	Unit Tests
Ensure functions behave deterministically.
	2.	Integration Tests
Validate the big circuits—plugins, config updates, signal routing.
	3.	Security Checks
Confirm new code respects boundaries. The security core is not optional plumbing; it’s foundational.
	4.	Observability Hooks
Every meaningful operation should emit a trace or structured log.
Think of logs as the autopsy reports of future bugs.

⸻

## Submitting a Pull Request

### A high-quality PR includes:
	•	A description of the architectural intention.
	•	Any diagrams or notes for reviewers.
	•	Tests demonstrating correctness.
	•	Zero surprises—no hidden side effects.

Merge discussions aren’t gatekeeping; they’re collective debugging.

⸻

### Community Norms
	•	Curiosity over certainty.
	•	Clarity over cleverness.
	•	Process over ego.
	•	Collaboration over siloing.

Every contributor increases the system’s resilience and intelligence.

⸻