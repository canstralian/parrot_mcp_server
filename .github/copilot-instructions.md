<!-- Copilot instructions tailored for the parrot_mcp_server repository -->

# Parrot MCP Server — AI assistant instructions

Short, actionable guidance to help AI coding agents be immediately productive in this repo.

- Project shape: small, Bash-first repository. Primary code lives under `rpi-scripts/` and `scripts/` and is driven by `cli.sh`.
- Core purpose: a lightweight Model Context Protocol (MCP) server implemented with portable Bash. Expect shell scripts, no language runtimes or package managers.

Key files and commands (quick references)
- `./rpi-scripts/start_mcp_server.sh` — start the MCP server locally.
- `./rpi-scripts/stop_mcp_server.sh` — stop it.
- `./rpi-scripts/test_mcp_local.sh` — local test harness for the MCP server.
- `./rpi-scripts/*.sh` and `./scripts/*.sh` — the reusable script library; run via `./cli.sh <script>`.
- Logs: `./logs/parrot.log` (tail -f to follow runtime output).

What to change and how
- When editing scripts, preserve the script shebang (for example, /usr/bin/env bash) and keep changes POSIX-friendly where possible.
- Make new scripts executable (`chmod +x`) and add them to `scripts/` if they should be exposed via `./cli.sh`.
- Follow existing naming patterns: `scripts/<name>.sh` and small, composable functions inside scripts.

Testing, linting and CI
- Repo uses ShellCheck and shfmt. Run locally before commits:
  - `shellcheck cli.sh scripts/*.sh rpi-scripts/*.sh`
  - `shfmt -w cli.sh scripts/*.sh rpi-scripts/*.sh`
- Tests: simple Bash tests and `rpi-scripts/test_mcp_local.sh`. CI runs these on push.

Conventions and patterns specific to this repo
- Minimal dependencies: avoid adding heavy language-specific toolchains. If required, document clearly in README.
- CLI wrapper: `cli.sh` is the canonical way to run library scripts — prefer modifying/adding scripts compatible with the CLI interface.
- Cron/setup: `./rpi-scripts/setup_cron.sh` sets up automated maintenance — changes that affect scheduling should update that script and note cron expectations in the PR.

Integration points and expectations
- The server communicates via filesystem and standard streams; expect scripts to read/write files under the repo or /tmp in CI-friendly ways.
- Keep any external integration (network, devices) toggled behind clear env vars so CI can run headless tests.

Examples to follow
- Adding a script: put `scripts/clean_logs.sh`, make executable, add a small usage block, verify via `./cli.sh clean_logs` and lint/tests.
- Start/stop flow: use `./rpi-scripts/start_mcp_server.sh` then `tail -f ./logs/parrot.log` to validate runtime behavior.

Editing this file
- If you find additional repo-specific rules or patterns, update this file with a short example and reference the touched file(s).

If something is unclear (missing env, CI secrets, or external hardware assumptions), ask the maintainer before making behavioral changes.
