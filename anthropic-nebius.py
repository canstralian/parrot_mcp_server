"""DeepSeek-V3 client via Nebius AI (OpenAI-compatible API).

cSpell:ignore nebius deepseek

Configuration via environment variables:
  NEBIUS_API_KEY        -- required: your Nebius API key
  DEEPSEEK_MODEL        -- optional: override the default model ID
  DEEPSEEK_SYSTEM       -- optional: override the default system prompt
  DEEPSEEK_STREAM       -- optional: "0" to disable streaming (default: on)
  DEEPSEEK_LOG_LEVEL    -- optional: logging level (DEBUG/INFO/WARNING/ERROR, default: WARNING)
  DEEPSEEK_MAX_RETRIES  -- optional: max retry attempts on transient errors (default: 3)
  DEEPSEEK_MAX_HISTORY  -- optional: max messages retained in REPL history (default: 100)

Usage:
  python anthropic-nebius.py                     # interactive multi-turn REPL
  python anthropic-nebius.py "your question"     # single-shot completion

Note: "Nebius" is a proper noun referring to Nebius AI service.
"""

from __future__ import annotations

import hashlib
import logging
import os
import secrets
import sys
import time

try:
    from openai import (
        OpenAI,
        APIConnectionError,
        APIError,
        APITimeoutError,
        AuthenticationError,
        RateLimitError,
    )
except ModuleNotFoundError as exc:
    if exc.name == "openai":
        sys.exit(
            "Missing dependency: 'openai'. Install it with:\n"
            "  python -m pip install openai"
        )
    raise


# ── Logging setup ─────────────────────────────────────────────────────


def _setup_logging() -> logging.Logger:
    level_name = os.environ.get("DEEPSEEK_LOG_LEVEL", "WARNING").upper()
    level = getattr(logging, level_name, logging.WARNING)
    logging.basicConfig(
        level=level,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
        stream=sys.stderr,
    )
    return logging.getLogger("nebius_client")


log = _setup_logging()


# ── Configuration ─────────────────────────────────────────────────────

NEBIUS_BASE_URL = "https://api.studio.nebius.ai/v1/"

DEFAULT_MODEL = "deepseek-ai/DeepSeek-V3"

DEFAULT_SYSTEM = (
    "You are a helpful, concise, and technically precise AI assistant. "
    "Answer clearly and directly, using code examples where relevant."
)

# Sampling parameters tuned for DeepSeek-V3's recommended defaults
MODEL_PARAMS: dict[str, int | float] = {
    "temperature": 0.6,
    "top_p": 0.95,
    "max_tokens": 8192,
}

_DEFAULT_MAX_RETRIES = 3
_RETRY_BASE_DELAY_S = 1.0
_RETRY_MAX_DELAY_S = 30.0

_MAX_USER_INPUT_CHARS = 32_768  # ~8 k tokens — hard cap before sending
_MAX_HISTORY_MESSAGES = 100  # configurable via DEEPSEEK_MAX_HISTORY


# ── Secure API-key fingerprint (hashing + salting) ────────────────────
#
# A per-process random salt so the fingerprint cannot be precomputed
# across sessions.  The raw key is NEVER written to any log.

_LOG_SALT: bytes = secrets.token_bytes(16)


def _key_fingerprint(api_key: str) -> str:
    """Return a salted PBKDF2/SHA-256 fingerprint for safe diagnostic logging.

    Only the first 16 hex characters (64 bits) are emitted — enough to
    identify which key is active without exposing any key material.
    """
    digest = hashlib.pbkdf2_hmac(
        "sha256",
        api_key.encode("utf-8"),
        _LOG_SALT,
        iterations=100_000,
    )
    return digest.hex()[:16]


# ── Custom exceptions ─────────────────────────────────────────────────


class ConfigurationError(RuntimeError):
    """Raised when required configuration is missing or invalid."""


class CompletionError(RuntimeError):
    """Raised when a completion request fails after all retries."""


# ── Client factory ────────────────────────────────────────────────────


def build_client() -> OpenAI:
    """Create an OpenAI-compatible client pointed at Nebius AI.

    Raises:
        ConfigurationError: if NEBIUS_API_KEY is absent or empty.
    """
    api_key = os.environ.get("NEBIUS_API_KEY", "").strip()
    if not api_key:
        raise ConfigurationError(
            "NEBIUS_API_KEY environment variable is not set or is empty."
        )
    log.debug("Client initialized (key fingerprint: %s)", _key_fingerprint(api_key))
    return OpenAI(api_key=api_key, base_url=NEBIUS_BASE_URL)


# ── Message helpers ───────────────────────────────────────────────────


def system_msg(text: str) -> dict[str, str]:
    return {"role": "system", "content": text}


def user_msg(text: str) -> dict[str, str]:
    return {"role": "user", "content": text}


def assistant_msg(text: str) -> dict[str, str]:
    return {"role": "assistant", "content": text}


def _sanitize_input(text: str) -> str:
    """Strip whitespace and enforce a hard character cap."""
    text = text.strip()
    if len(text) > _MAX_USER_INPUT_CHARS:
        log.warning(
            "Input truncated from %d to %d characters.",
            len(text),
            _MAX_USER_INPUT_CHARS,
        )
        text = text[:_MAX_USER_INPUT_CHARS]
    return text


def build_messages(
    user_text: str,
    *,
    system: str = DEFAULT_SYSTEM,
    history: list[dict[str, str]] | None = None,
) -> list[dict[str, str]]:
    """Assemble the full message list: system + history + new user turn."""
    messages: list[dict[str, str]] = [system_msg(system)]
    if history:
        messages.extend(history)
    messages.append(user_msg(user_text))
    return messages


# ── Retry helpers ─────────────────────────────────────────────────────

# Errors that are transient and safe to retry
_TRANSIENT_ERRORS = (APIConnectionError, APITimeoutError, RateLimitError)


def _retry_delay(attempt: int) -> float:
    """Exponential back-off with full jitter, capped at _RETRY_MAX_DELAY_S.

    Using *full jitter* (random value in [0, cap]) avoids thundering-herd
    problems when many clients back off simultaneously.
    """
    cap = min(_RETRY_BASE_DELAY_S * (2**attempt), _RETRY_MAX_DELAY_S)
    # secrets.randbelow gives a cryptographically secure integer in [0, n)
    return secrets.randbelow(max(1, int(cap * 1_000))) / 1_000


# ── Completion ────────────────────────────────────────────────────────


def complete(
    client: OpenAI,
    messages: list[dict[str, str]],
    *,
    model: str = DEFAULT_MODEL,
    stream: bool = True,
    max_retries: int = _DEFAULT_MAX_RETRIES,
    **override_params: int | float,
) -> str:
    """Send a completion request and return the assistant reply as a string.

    When *stream* is ``True`` the response tokens are printed to stdout as
    they arrive; the full reply is still returned for programmatic use.

    Transient errors (network, timeout, rate-limit) are retried with
    exponential back-off and full jitter up to *max_retries* times.

    Raises:
        CompletionError: on authentication failure, permanent API error, or
                         exhausted retries.
    """
    params = {**MODEL_PARAMS, **override_params}

    response = None
    for attempt in range(max_retries + 1):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=messages,  # type: ignore[arg-type]
                stream=stream,
                **params,  # type: ignore[arg-type]
            )
            break  # request succeeded

        except AuthenticationError as exc:
            # Non-retryable — bad key
            raise CompletionError(
                "Authentication failed. Verify your NEBIUS_API_KEY."
            ) from exc

        except _TRANSIENT_ERRORS as exc:
            if attempt < max_retries:
                delay = _retry_delay(attempt)
                log.warning(
                    "Transient error (%s); retrying in %.2fs (attempt %d/%d).",
                    type(exc).__name__,
                    delay,
                    attempt + 1,
                    max_retries,
                )
                time.sleep(delay)
            else:
                raise CompletionError(
                    f"Request failed after {max_retries + 1} attempt(s): {exc}"
                ) from exc

        except APIError as exc:
            # Non-retryable API error (e.g. 400 Bad Request)
            raise CompletionError(
                f"API error ({getattr(exc, 'status_code', 'unknown')}): "
                f"{getattr(exc, 'message', str(exc))}"
            ) from exc

    if response is None:
        # Should be unreachable, but defend against it
        raise CompletionError("No response received after retry loop.")

    # ── Consume the response ──────────────────────────────────────────
    if stream:
        chunks: list[str] = []
        try:
            for chunk in response:  # type: ignore[union-attr]
                if not chunk.choices:
                    continue
                delta = chunk.choices[0].delta.content or ""
                print(delta, end="", flush=True)
                chunks.append(delta)
        except Exception as exc:  # noqa: BLE001
            # Return whatever was collected before the interruption
            log.error("Stream interrupted after %d chunk(s): %s", len(chunks), exc)
        finally:
            print()  # trailing newline regardless of error
        return "".join(chunks)

    # Non-streaming path
    try:
        content = response.choices[0].message.content  # type: ignore[union-attr]
        return content or ""
    except (IndexError, AttributeError) as exc:
        log.error("Unexpected response structure: %s", exc)
        return ""


# ── Single-shot helper ────────────────────────────────────────────────


def single_shot(
    client: OpenAI,
    user_text: str,
    *,
    system: str = DEFAULT_SYSTEM,
    model: str = DEFAULT_MODEL,
    stream: bool = True,
    max_retries: int = _DEFAULT_MAX_RETRIES,
) -> str:
    """One-off completion with no retained history.

    Raises:
        CompletionError: propagated from :func:`complete`.
    """
    user_text = _sanitize_input(user_text)
    if not user_text:
        log.warning("single_shot called with empty input; returning empty string.")
        return ""
    messages = build_messages(user_text, system=system)
    return complete(
        client, messages, model=model, stream=stream, max_retries=max_retries
    )


# ── History management ────────────────────────────────────────────────


def _trim_history(
    history: list[dict[str, str]], max_messages: int
) -> list[dict[str, str]]:
    """Drop the oldest exchanges to keep history within *max_messages*.

    Messages are always dropped in user+assistant pairs so the history
    never starts mid-exchange or with a dangling assistant turn.
    """
    if len(history) <= max_messages:
        return history

    excess = len(history) - max_messages
    # Round up to the next even number to always drop complete pairs
    excess += excess % 2
    trimmed = history[excess:]
    log.info("History trimmed: dropped %d oldest messages.", excess)
    return trimmed


# ── Interactive multi-turn REPL ───────────────────────────────────────


def conversation_loop(
    client: OpenAI,
    *,
    system: str = DEFAULT_SYSTEM,
    model: str = DEFAULT_MODEL,
    stream: bool = True,
    max_retries: int = _DEFAULT_MAX_RETRIES,
    max_history: int = _MAX_HISTORY_MESSAGES,
) -> None:
    """Run a multi-turn conversation, keeping full message history in memory.

    Completion errors are caught and displayed without terminating the REPL,
    so the user can correct their input and continue the session.
    """
    history: list[dict[str, str]] = []

    print(f"DeepSeek ({model})  —  type 'quit' or Ctrl-C to exit\n")

    while True:
        try:
            raw = input("You: ")
        except (EOFError, KeyboardInterrupt):
            print("\nSession ended.")
            break

        user_input = _sanitize_input(raw)
        if not user_input:
            continue
        if user_input.lower() in {"quit", "exit", "q"}:
            break

        messages = build_messages(user_input, system=system, history=history)

        print("Assistant: ", end="", flush=True)
        try:
            reply = complete(
                client,
                messages,
                model=model,
                stream=stream,
                max_retries=max_retries,
            )
        except CompletionError as exc:
            log.error("Completion failed: %s", exc)
            print(f"\n[Error] {exc}\n")
            continue  # graceful: keep the REPL alive without corrupting history

        # Only extend history on success
        history.extend([user_msg(user_input), assistant_msg(reply)])
        history = _trim_history(history, max_history)


# ── Entry point ───────────────────────────────────────────────────────


def main() -> None:
    model = os.environ.get("DEEPSEEK_MODEL", DEFAULT_MODEL)
    system = os.environ.get("DEEPSEEK_SYSTEM", DEFAULT_SYSTEM)
    stream = os.environ.get("DEEPSEEK_STREAM", "1") != "0"
    max_retries = int(os.environ.get("DEEPSEEK_MAX_RETRIES", str(_DEFAULT_MAX_RETRIES)))
    max_history = int(
        os.environ.get("DEEPSEEK_MAX_HISTORY", str(_MAX_HISTORY_MESSAGES))
    )

    try:
        client = build_client()
    except ConfigurationError as exc:
        log.critical("Configuration error: %s", exc)
        sys.exit(f"Error: {exc}")

    if len(sys.argv) > 1:
        user_text = " ".join(sys.argv[1:])
        try:
            single_shot(
                client,
                user_text,
                system=system,
                model=model,
                stream=stream,
                max_retries=max_retries,
            )
        except CompletionError as exc:
            log.error("Single-shot failed: %s", exc)
            sys.exit(f"Error: {exc}")
    else:
        conversation_loop(
            client,
            system=system,
            model=model,
            stream=stream,
            max_retries=max_retries,
            max_history=max_history,
        )


if __name__ == "__main__":
    main()
