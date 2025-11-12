# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added
- POSIX-first logging and metrics system
  - Structured JSON logging with automatic sensitive data sanitization (`scripts/logging.sh`)
  - Tool execution wrapper with Prometheus metrics (`scripts/wrap_tool_exec.sh`)
  - Grep-based log search utility (`scripts/search_logs.sh`)
  - Real-time SSE log streaming server (`rpi-scripts/log_stream_sse.py`)
  - Logrotate configuration for automatic log management (`scripts/logrotate_parrot.conf`)
  - Comprehensive test harness with 6 tests (`rpi-scripts/test_logging.sh`)
  - Documentation for logging and metrics system (`docs/LOGGING_AND_METRICS.md`)

- Initial public release: core CLI, system maintenance scripts, automation, and cron setup.
