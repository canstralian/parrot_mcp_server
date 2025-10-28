
# GEMINI.md — Parrot MCP Server Project

This file provides project-specific instructions and context for using Google Gemini or similar LLMs with the Parrot MCP Server codebase.

---

## Project Context

- **Project:** Parrot MCP Server
- **Purpose:** Lightweight, modular, and portable Model Context Protocol (MCP) server in POSIX Bash.
- **Primary Use:** Structured message exchange between AI agents and local tools/services, with a focus on transparency, auditability, and testability.

---

## Gemini/LLM Integration Guidance

- **Spec-driven:** All code and automation should follow the official MCP Server spec and Anthropic best practices.
- **Shell-first:** Scripts are POSIX Bash, portable, and must avoid hidden dependencies.
- **Testing:** Use `rpi-scripts/test_mcp_local.sh` and `tests/` for protocol compliance. Add new tests for any protocol-relevant change.
- **Logging:** All protocol interactions must be logged in `./logs/parrot.log` for auditability.
- **Automation:** When automating tasks (e.g., purple team, system checks), use the MCP message format and ensure results are observable via logs or test harnesses.

---

## MCP Message Formats

LLMs should use structured JSON messages for MCP communication. Example formats:

### Request Message

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/call",
  "params": {
    "name": "run_script",
    "arguments": {
      "script": "check_disk",
      "args": ["--verbose"]
    }
  }
}
```

### Response Message

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "content": [
      {
        "type": "text",
        "text": "Disk check completed. Usage: 45% on /dev/sda1"
      }
    ]
  }
}
```

### Error Message

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32601,
    "message": "Method not found",
    "data": {
      "script": "invalid_script"
    }
  }
}
```

---

## Example: LLM Automation Flow

1. LLM receives a structured MCP message (JSON) from a client or orchestrator.
2. LLM triggers a Bash script via the MCP server (using `cli.sh` or direct script call).
3. Script performs the requested action, logs results, and returns a structured response (MCP message or log entry).
4. LLM parses the log or output, and responds to the client with results or next steps.

### Specific Example: System Update Automation

- **Trigger:** LLM receives MCP request to update system packages.
- **Action:** LLM calls `./cli.sh system_update` via MCP.
- **Logging:** Script logs progress to `./logs/parrot.log` with message ID `SYS_UPD_001`.
- **Response:** LLM returns success/failure status based on log parsing.

---

## Purple Team Integration

Purple team scripts combine red team (offensive) and blue team (defensive) techniques for security testing. In Parrot MCP Server:

- **Automation:** Use MCP to trigger security scans, vulnerability checks, or incident response actions.
- **Scripts:** Create scripts like `purple_scan.sh` that run nmap, check for open ports, and log findings.
- **LLM Role:** LLMs can orchestrate scans, analyze results, and suggest remediation steps.
- **Example Flow:**
  1. LLM initiates purple team scan via MCP.
  2. Script runs security checks and logs to `./logs/parrot.log`.
  3. LLM reviews logs and generates security report.

---

## Best Practices

- **Explicitness:** Favor clear, auditable shell logic over cleverness.
- **Edge Cases:** Document protocol boundaries and error handling in comments.
- **Portability:** Avoid language-specific toolchains; scripts should run on any modern Linux system.
- **Security:** Never expose sensitive data in logs or outputs. Use environment variables for secrets if needed.

---

## References

- See `.github/copilot-instructions.md` for AI agent coding conventions.
- See `README.md` and `docs/LOGGING.md` for project overview and logging details.
- For hardware context, see `HARDWARE_BOM.md`.
