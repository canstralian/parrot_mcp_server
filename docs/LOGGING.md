# Parrot MCP Server Logging Guide

This document describes the logging conventions, log formats, and troubleshooting tips for the Parrot MCP Server and its script library.

---

## Log File Locations

- **Server and script logs:** `./logs/parrot.log`
- **CLI error log:** `./rpi-scripts/cli_error.log`

---

## Log Format

All log entries follow this format:

```
[YYYY-MM-DD HH:MM:SS] [LEVEL] [msgid:UNIQUE_ID] message text
```

- **LEVEL**: INFO, WARN, ERROR
- **msgid**: Nanosecond-precision timestamp for traceability
- **message text**: Human-readable event or error description

### Examples

```
[2025-10-28 21:00:00] [INFO] [msgid:1727480400000000000] MCP server started (stub)
[2025-10-28 21:00:01] [ERROR] [msgid:1727480401000000000] Malformed MCP message received
[2025-10-28 21:00:02] [WARN] [msgid:1727480402000000000] No MCP server PID file found on stop
```

---

## Logging Best Practices

- **Log all errors and warnings** with [ERROR] or [WARN] and a unique message ID.
- **Log normal events** (startup, shutdown, message received) with [INFO].
- **Include context** (script name, PID, message type) in the log message when possible.
- **Graceful fallbacks**: Always log when a fallback or exception occurs (e.g., missing file, failed process kill).

---

## Troubleshooting

- If a script fails, check both `parrot.log` and `cli_error.log` for [ERROR] entries and message IDs.
- Use the message ID to correlate events across logs.
- If the server does not start or stop, look for [ERROR] or [WARN] entries about PID files or permissions.
- For protocol issues, ensure that valid and malformed messages are both logged and handled as shown in the test harness.

---

## Extending Logging

- When adding new scripts, use the same log format and conventions.
- For new error types, document them here for future maintainers.
