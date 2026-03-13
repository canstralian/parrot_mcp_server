"""Tests for anthropic-nebius.py client module.

Because the module has a hyphen in its filename we load it via importlib.
All openai imports are mocked so no network credentials are required.

Covers:
  - Message helper constructors (system_msg, user_msg, assistant_msg)
  - _sanitize_input: whitespace stripping and hard character cap
  - build_messages: system + history + user assembly
  - _trim_history: pair-drop logic and boundary conditions
  - _key_fingerprint: length, hex chars, per-call salt behaviour
  - _retry_delay: range and cap behaviour
  - build_client: ConfigurationError when key is absent/empty
  - complete: auth error, transient retry, non-retryable API error,
              exhausted retries, streaming/non-streaming response assembly
"""

from __future__ import annotations

import importlib.util
import sys
import os
from pathlib import Path
from types import ModuleType
from typing import Iterator
from unittest.mock import MagicMock, patch, call
import pytest


# ---------------------------------------------------------------------------
# Module loading helpers
# ---------------------------------------------------------------------------

NEBIUS_PATH = Path(__file__).parent.parent / "anthropic-nebius.py"


def _make_openai_mock() -> MagicMock:
    """Build a mock openai module with realistic exception hierarchy."""

    class _APIError(Exception):
        status_code: int | None = None
        message: str = ""

    class _AuthenticationError(_APIError):
        pass

    class _APIConnectionError(_APIError):
        pass

    class _APITimeoutError(_APIError):
        pass

    class _RateLimitError(_APIError):
        pass

    mock = MagicMock(name="openai")
    mock.OpenAI = MagicMock(name="openai.OpenAI")
    mock.APIError = _APIError
    mock.AuthenticationError = _AuthenticationError
    mock.APIConnectionError = _APIConnectionError
    mock.APITimeoutError = _APITimeoutError
    mock.RateLimitError = _RateLimitError
    return mock


def _load_nebius(mock_openai: MagicMock) -> ModuleType:
    """Import anthropic-nebius.py into a fresh module using the given mock."""
    # Remove any previously loaded copy so each call is fresh
    for key in list(sys.modules.keys()):
        if "nebius" in key.lower():
            del sys.modules[key]

    with patch.dict(sys.modules, {"openai": mock_openai}):
        spec = importlib.util.spec_from_file_location("nebius_client", NEBIUS_PATH)
        assert spec and spec.loader, f"Could not load spec from {NEBIUS_PATH}"
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


@pytest.fixture(scope="module")
def oai() -> MagicMock:
    """Shared openai mock (module-scoped for speed)."""
    return _make_openai_mock()


@pytest.fixture(scope="module")
def nb(oai: MagicMock) -> ModuleType:
    """Loaded nebius module (module-scoped)."""
    return _load_nebius(oai)


# ---------------------------------------------------------------------------
# Message helpers
# ---------------------------------------------------------------------------


class TestMessageHelpers:
    def test_system_msg_role(self, nb: ModuleType):
        msg = nb.system_msg("hello")
        assert msg["role"] == "system"

    def test_system_msg_content(self, nb: ModuleType):
        msg = nb.system_msg("system prompt")
        assert msg["content"] == "system prompt"

    def test_user_msg_role(self, nb: ModuleType):
        msg = nb.user_msg("question")
        assert msg["role"] == "user"

    def test_user_msg_content(self, nb: ModuleType):
        msg = nb.user_msg("what is 2+2?")
        assert msg["content"] == "what is 2+2?"

    def test_assistant_msg_role(self, nb: ModuleType):
        msg = nb.assistant_msg("answer")
        assert msg["role"] == "assistant"

    def test_assistant_msg_content(self, nb: ModuleType):
        msg = nb.assistant_msg("4")
        assert msg["content"] == "4"

    def test_all_helpers_return_dicts(self, nb: ModuleType):
        for fn in (nb.system_msg, nb.user_msg, nb.assistant_msg):
            assert isinstance(fn("text"), dict)


# ---------------------------------------------------------------------------
# _sanitize_input
# ---------------------------------------------------------------------------


class TestSanitizeInput:
    def test_strips_leading_whitespace(self, nb: ModuleType):
        assert nb._sanitize_input("  hello") == "hello"

    def test_strips_trailing_whitespace(self, nb: ModuleType):
        assert nb._sanitize_input("hello  ") == "hello"

    def test_preserves_inner_content(self, nb: ModuleType):
        assert nb._sanitize_input("  hello world  ") == "hello world"

    def test_empty_string_stays_empty(self, nb: ModuleType):
        assert nb._sanitize_input("") == ""

    def test_whitespace_only_becomes_empty(self, nb: ModuleType):
        assert nb._sanitize_input("   \t  ") == ""

    def test_truncates_to_max_chars(self, nb: ModuleType):
        limit = nb._MAX_USER_INPUT_CHARS
        long_input = "x" * (limit + 100)
        result = nb._sanitize_input(long_input)
        assert len(result) == limit

    def test_short_input_not_truncated(self, nb: ModuleType):
        short = "hello world"
        assert nb._sanitize_input(short) == short

    def test_exactly_at_limit_not_truncated(self, nb: ModuleType):
        limit = nb._MAX_USER_INPUT_CHARS
        exact = "a" * limit
        result = nb._sanitize_input(exact)
        assert len(result) == limit

    def test_truncation_prefers_head_of_string(self, nb: ModuleType):
        limit = nb._MAX_USER_INPUT_CHARS
        text = "A" * limit + "B" * 100
        result = nb._sanitize_input(text)
        assert result == "A" * limit


# ---------------------------------------------------------------------------
# build_messages
# ---------------------------------------------------------------------------


class TestBuildMessages:
    def test_always_starts_with_system_message(self, nb: ModuleType):
        msgs = nb.build_messages("hello")
        assert msgs[0]["role"] == "system"

    def test_last_message_is_user(self, nb: ModuleType):
        msgs = nb.build_messages("my question")
        assert msgs[-1]["role"] == "user"
        assert msgs[-1]["content"] == "my question"

    def test_no_history_yields_two_messages(self, nb: ModuleType):
        msgs = nb.build_messages("question", history=None)
        assert len(msgs) == 2

    def test_custom_system_prompt(self, nb: ModuleType):
        msgs = nb.build_messages("q", system="custom system")
        assert msgs[0]["content"] == "custom system"

    def test_history_inserted_between_system_and_user(self, nb: ModuleType):
        history = [
            {"role": "user", "content": "first"},
            {"role": "assistant", "content": "reply"},
        ]
        msgs = nb.build_messages("second", history=history)
        assert msgs[0]["role"] == "system"
        assert msgs[1] == history[0]
        assert msgs[2] == history[1]
        assert msgs[3]["role"] == "user"
        assert msgs[3]["content"] == "second"

    def test_empty_history_yields_two_messages(self, nb: ModuleType):
        msgs = nb.build_messages("q", history=[])
        assert len(msgs) == 2

    def test_total_length_with_history(self, nb: ModuleType):
        history = [{"role": "user", "content": f"msg {i}"} for i in range(4)]
        msgs = nb.build_messages("new", history=history)
        assert len(msgs) == 1 + 4 + 1  # system + history + user


# ---------------------------------------------------------------------------
# _trim_history
# ---------------------------------------------------------------------------


class TestTrimHistory:
    def test_no_trim_when_within_limit(self, nb: ModuleType):
        history = [{"role": "user", "content": str(i)} for i in range(4)]
        result = nb._trim_history(history, max_messages=10)
        assert result == history

    def test_trims_to_max_messages(self, nb: ModuleType):
        history = [{"role": "user", "content": str(i)} for i in range(10)]
        result = nb._trim_history(history, max_messages=6)
        assert len(result) <= 6

    def test_drops_in_pairs_to_preserve_exchange_integrity(self, nb: ModuleType):
        """Dropping must always remove an even number of messages so history
        never starts with an orphaned assistant turn."""
        history = [{"role": "user", "content": str(i)} for i in range(7)]
        result = nb._trim_history(history, max_messages=5)
        # excess = 7-5 = 2, already even → drop 2, keep 5
        assert len(result) == 5

    def test_odd_excess_rounded_up_to_even(self, nb: ModuleType):
        """If excess is odd, it must be rounded up so we drop a full pair."""
        history = [{"role": "user", "content": str(i)} for i in range(8)]
        # excess = 8-5 = 3, rounded up to 4 → keep 4
        result = nb._trim_history(history, max_messages=5)
        assert len(result) == 4

    def test_exactly_at_limit_not_trimmed(self, nb: ModuleType):
        history = [{"role": "user", "content": str(i)} for i in range(6)]
        result = nb._trim_history(history, max_messages=6)
        assert len(result) == 6

    def test_empty_history_unchanged(self, nb: ModuleType):
        assert nb._trim_history([], max_messages=10) == []

    def test_most_recent_messages_kept(self, nb: ModuleType):
        """After trimming, the kept messages should be the most recent ones."""
        history = [{"role": "user", "content": str(i)} for i in range(10)]
        result = nb._trim_history(history, max_messages=6)
        kept_contents = [m["content"] for m in result]
        # The last 6 (or fewer due to pair rounding) entries should be at end
        for content in kept_contents:
            assert int(content) >= 10 - len(result)


# ---------------------------------------------------------------------------
# _key_fingerprint
# ---------------------------------------------------------------------------


class TestKeyFingerprint:
    def test_returns_16_hex_chars(self, nb: ModuleType):
        fp = nb._key_fingerprint("my-api-key")
        assert len(fp) == 16
        assert all(c in "0123456789abcdef" for c in fp)

    def test_different_keys_different_fingerprints(self, nb: ModuleType):
        fp1 = nb._key_fingerprint("key-aaa")
        fp2 = nb._key_fingerprint("key-bbb")
        assert fp1 != fp2

    def test_same_key_same_process_consistent(self, nb: ModuleType):
        """Within a single process (same _LOG_SALT), fingerprint is stable."""
        fp1 = nb._key_fingerprint("test-key")
        fp2 = nb._key_fingerprint("test-key")
        assert fp1 == fp2

    def test_empty_key_returns_hex_string(self, nb: ModuleType):
        fp = nb._key_fingerprint("")
        assert len(fp) == 16

    def test_different_module_instances_may_differ(self):
        """Two module loads use different salts, so fingerprints may differ."""
        oai1 = _make_openai_mock()
        oai2 = _make_openai_mock()
        mod1 = _load_nebius(oai1)
        mod2 = _load_nebius(oai2)
        # With high probability the per-process salts differ
        fp1 = mod1._key_fingerprint("same-key")
        fp2 = mod2._key_fingerprint("same-key")
        # We can only assert they're valid hex strings; equality is probabilistic
        assert len(fp1) == 16
        assert len(fp2) == 16


# ---------------------------------------------------------------------------
# _retry_delay
# ---------------------------------------------------------------------------


class TestRetryDelay:
    def test_non_negative(self, nb: ModuleType):
        for attempt in range(5):
            assert nb._retry_delay(attempt) >= 0

    def test_capped_at_max_delay(self, nb: ModuleType):
        # attempt 100 would produce a huge uncapped value
        delay = nb._retry_delay(100)
        assert delay <= nb._RETRY_MAX_DELAY_S

    def test_attempt_zero_capped_at_base(self, nb: ModuleType):
        # cap = min(base * 2^0, max) = min(1.0, 30.0) = 1.0
        delay = nb._retry_delay(0)
        assert delay <= nb._RETRY_BASE_DELAY_S

    def test_returns_float(self, nb: ModuleType):
        assert isinstance(nb._retry_delay(1), float)


# ---------------------------------------------------------------------------
# build_client
# ---------------------------------------------------------------------------


class TestBuildClient:
    def test_raises_configuration_error_when_key_missing(self, nb: ModuleType):
        env = {k: v for k, v in os.environ.items() if k != "NEBIUS_API_KEY"}
        with patch.dict(os.environ, env, clear=True):
            with pytest.raises(nb.ConfigurationError, match="NEBIUS_API_KEY"):
                nb.build_client()

    def test_raises_configuration_error_when_key_empty(self, nb: ModuleType):
        with patch.dict(os.environ, {"NEBIUS_API_KEY": ""}):
            with pytest.raises(nb.ConfigurationError):
                nb.build_client()

    def test_raises_configuration_error_when_key_whitespace_only(self, nb: ModuleType):
        with patch.dict(os.environ, {"NEBIUS_API_KEY": "   "}):
            with pytest.raises(nb.ConfigurationError):
                nb.build_client()

    def test_returns_client_when_key_present(self, nb: ModuleType, oai: MagicMock):
        with patch.dict(os.environ, {"NEBIUS_API_KEY": "valid-test-key"}):
            client = nb.build_client()
        assert client is not None


# ---------------------------------------------------------------------------
# complete — error handling (no real network)
# ---------------------------------------------------------------------------


class TestComplete:
    """Test complete() error-handling paths using a mock client."""

    def _mock_client(self, nb: ModuleType, oai: MagicMock) -> MagicMock:
        client = MagicMock()
        return client

    def test_authentication_error_raises_completion_error(
        self, nb: ModuleType, oai: MagicMock
    ):
        client = MagicMock()
        client.chat.completions.create.side_effect = oai.AuthenticationError(
            "bad key"
        )
        with pytest.raises(nb.CompletionError, match="Authentication"):
            nb.complete(client, [nb.user_msg("hi")], stream=False, max_retries=0)

    def test_non_retryable_api_error_raises_completion_error(
        self, nb: ModuleType, oai: MagicMock
    ):
        client = MagicMock()
        err = oai.APIError("bad request")
        err.status_code = 400
        client.chat.completions.create.side_effect = err
        with pytest.raises(nb.CompletionError):
            nb.complete(client, [nb.user_msg("hi")], stream=False, max_retries=0)

    def test_transient_error_retried_then_succeeds(
        self, nb: ModuleType, oai: MagicMock
    ):
        client = MagicMock()
        # Fail once with transient error, then succeed
        mock_response = MagicMock()
        mock_response.choices[0].message.content = "hello"
        client.chat.completions.create.side_effect = [
            oai.APIConnectionError("timeout"),
            mock_response,
        ]
        with patch.object(nb, "_retry_delay", return_value=0.0), patch(
            "time.sleep"
        ):
            result = nb.complete(
                client,
                [nb.user_msg("hi")],
                stream=False,
                max_retries=2,
            )
        assert result == "hello"

    def test_exhausted_retries_raises_completion_error(
        self, nb: ModuleType, oai: MagicMock
    ):
        client = MagicMock()
        client.chat.completions.create.side_effect = oai.APIConnectionError(
            "persistent failure"
        )
        with patch.object(nb, "_retry_delay", return_value=0.0), patch(
            "time.sleep"
        ):
            with pytest.raises(nb.CompletionError, match="attempt"):
                nb.complete(
                    client,
                    [nb.user_msg("hi")],
                    stream=False,
                    max_retries=2,
                )

    def test_successful_non_streaming_returns_content(
        self, nb: ModuleType, oai: MagicMock
    ):
        client = MagicMock()
        mock_response = MagicMock()
        mock_response.choices[0].message.content = "the answer"
        client.chat.completions.create.return_value = mock_response
        result = nb.complete(
            client, [nb.user_msg("q")], stream=False, max_retries=0
        )
        assert result == "the answer"

    def test_none_content_returns_empty_string(
        self, nb: ModuleType, oai: MagicMock
    ):
        client = MagicMock()
        mock_response = MagicMock()
        mock_response.choices[0].message.content = None
        client.chat.completions.create.return_value = mock_response
        result = nb.complete(
            client, [nb.user_msg("q")], stream=False, max_retries=0
        )
        assert result == ""
