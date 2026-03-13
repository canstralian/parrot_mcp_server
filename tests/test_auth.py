"""Tests for parrot_mcp_server.auth module.

Covers:
  - Engagement dataclass construction
  - register_engagement()
  - require_authorization() — scope, time window, error messages
  - engagement_fingerprint() — determinism, uniqueness, length
"""

import pytest
from datetime import datetime, timezone, timedelta
from parrot_mcp_server import auth
from parrot_mcp_server.auth import (
    Engagement,
    register_engagement,
    require_authorization,
    engagement_fingerprint,
)


# ── Helpers ────────────────────────────────────────────────────────────


def _now() -> datetime:
    return datetime.now(tz=timezone.utc)


def make_engagement(**overrides) -> Engagement:
    """Return a default active engagement. Override any field via kwargs."""
    now = _now()
    defaults: dict = dict(
        engagement_id="eng-001",
        scope=["192.168.1.", "10.0.0.", "example.com"],
        authorized_by="alice@example.com",
        start_utc=now - timedelta(hours=1),
        end_utc=now + timedelta(hours=23),
        rules_of_engagement="Standard RoE: no DoS attacks.",
        teams=["red"],
    )
    defaults.update(overrides)
    return Engagement(**defaults)


@pytest.fixture(autouse=True)
def clear_engagements():
    """Isolate each test by clearing the global registry."""
    auth._ACTIVE_ENGAGEMENTS.clear()
    yield
    auth._ACTIVE_ENGAGEMENTS.clear()


# ── Engagement dataclass ───────────────────────────────────────────────


class TestEngagementDataclass:
    def test_basic_construction(self):
        eng = make_engagement()
        assert eng.engagement_id == "eng-001"
        assert "192.168.1." in eng.scope
        assert eng.authorized_by == "alice@example.com"
        assert eng.teams == ["red"]

    def test_teams_defaults_to_empty_list(self):
        """teams field has a default_factory=list so it defaults to []."""
        now = _now()
        eng = Engagement(
            engagement_id="eng-002",
            scope=["*"],
            authorized_by="bob@example.com",
            start_utc=now - timedelta(hours=1),
            end_utc=now + timedelta(hours=1),
            rules_of_engagement="RoE text",
        )
        assert eng.teams == []

    def test_multiple_scope_entries(self):
        eng = make_engagement(scope=["10.0.0.", "172.16.", "example.org"])
        assert len(eng.scope) == 3

    def test_wildcard_scope(self):
        eng = make_engagement(scope=["*"])
        assert eng.scope == ["*"]

    def test_multiple_teams(self):
        eng = make_engagement(teams=["red", "purple", "osint"])
        assert len(eng.teams) == 3

    def test_start_before_end(self):
        now = _now()
        eng = make_engagement(
            start_utc=now - timedelta(hours=2),
            end_utc=now + timedelta(hours=2),
        )
        assert eng.start_utc < eng.end_utc


# ── register_engagement ────────────────────────────────────────────────


class TestRegisterEngagement:
    def test_returns_engagement_id(self):
        eng = make_engagement()
        returned_id = register_engagement(eng)
        assert returned_id == "eng-001"

    def test_stores_engagement_in_registry(self):
        eng = make_engagement()
        register_engagement(eng)
        assert "eng-001" in auth._ACTIVE_ENGAGEMENTS
        assert auth._ACTIVE_ENGAGEMENTS["eng-001"] is eng

    def test_multiple_engagements_stored_independently(self):
        eng1 = make_engagement(engagement_id="eng-001")
        eng2 = make_engagement(engagement_id="eng-002")
        register_engagement(eng1)
        register_engagement(eng2)
        assert "eng-001" in auth._ACTIVE_ENGAGEMENTS
        assert "eng-002" in auth._ACTIVE_ENGAGEMENTS
        assert auth._ACTIVE_ENGAGEMENTS["eng-001"] is eng1
        assert auth._ACTIVE_ENGAGEMENTS["eng-002"] is eng2

    def test_overwrite_same_id(self):
        """Registering with the same ID replaces the previous engagement."""
        eng_v1 = make_engagement(authorized_by="alice@example.com")
        eng_v2 = make_engagement(authorized_by="bob@example.com")
        register_engagement(eng_v1)
        register_engagement(eng_v2)
        stored = auth._ACTIVE_ENGAGEMENTS["eng-001"]
        assert stored.authorized_by == "bob@example.com"

    def test_registry_empty_before_registration(self):
        assert len(auth._ACTIVE_ENGAGEMENTS) == 0


# ── require_authorization ──────────────────────────────────────────────


class TestRequireAuthorization:
    def test_valid_returns_engagement(self):
        eng = make_engagement()
        register_engagement(eng)
        result = require_authorization("eng-001", "192.168.1.100")
        assert result is eng

    def test_unknown_id_raises_permission_error(self):
        with pytest.raises(PermissionError, match="No active engagement"):
            require_authorization("does-not-exist", "10.0.0.1")

    def test_error_message_includes_missing_id(self):
        with pytest.raises(PermissionError) as exc_info:
            require_authorization("missing-eng", "10.0.0.1")
        assert "missing-eng" in str(exc_info.value)

    def test_expired_engagement_raises(self):
        now = _now()
        eng = make_engagement(
            start_utc=now - timedelta(hours=3),
            end_utc=now - timedelta(hours=1),  # ended 1 hour ago
        )
        register_engagement(eng)
        with pytest.raises(PermissionError, match="outside its authorized window"):
            require_authorization("eng-001", "192.168.1.1")

    def test_future_engagement_not_yet_started_raises(self):
        now = _now()
        eng = make_engagement(
            start_utc=now + timedelta(hours=1),  # starts in 1 hour
            end_utc=now + timedelta(hours=2),
        )
        register_engagement(eng)
        with pytest.raises(PermissionError, match="outside its authorized window"):
            require_authorization("eng-001", "192.168.1.1")

    def test_target_matches_scope_prefix(self):
        eng = make_engagement(scope=["192.168.1."])
        register_engagement(eng)
        # Should not raise for any IP in the /24
        require_authorization("eng-001", "192.168.1.42")
        require_authorization("eng-001", "192.168.1.255")

    def test_target_out_of_scope_raises(self):
        eng = make_engagement(scope=["192.168.1.", "10.0.0."])
        register_engagement(eng)
        with pytest.raises(PermissionError, match="NOT in scope"):
            require_authorization("eng-001", "172.16.0.1")

    def test_error_message_includes_target_when_out_of_scope(self):
        eng = make_engagement(scope=["10.0.0."])
        register_engagement(eng)
        with pytest.raises(PermissionError) as exc_info:
            require_authorization("eng-001", "172.16.99.99")
        assert "172.16.99.99" in str(exc_info.value)

    def test_error_message_includes_scope_when_out_of_scope(self):
        eng = make_engagement(scope=["10.0.0."])
        register_engagement(eng)
        with pytest.raises(PermissionError) as exc_info:
            require_authorization("eng-001", "172.16.0.1")
        assert "10.0.0." in str(exc_info.value)

    def test_wildcard_scope_allows_any_target(self):
        eng = make_engagement(scope=["*"])
        register_engagement(eng)
        require_authorization("eng-001", "192.0.2.1")
        require_authorization("eng-001", "arbitrary.internal.example")

    def test_exact_hostname_match(self):
        eng = make_engagement(scope=["example.com"])
        register_engagement(eng)
        require_authorization("eng-001", "example.com")

    def test_scope_prefix_matches_subpath(self):
        """'example.com' as scope matches 'example.com/api/v1'."""
        eng = make_engagement(scope=["example.com"])
        register_engagement(eng)
        require_authorization("eng-001", "example.com/api/v1")

    def test_partial_prefix_does_not_match_different_subnet(self):
        eng = make_engagement(scope=["192.168.1."])
        register_engagement(eng)
        with pytest.raises(PermissionError):
            require_authorization("eng-001", "192.168.2.1")

    def test_multiple_scope_entries_any_match_is_sufficient(self):
        eng = make_engagement(scope=["10.0.0.", "172.16.", "192.168."])
        register_engagement(eng)
        require_authorization("eng-001", "10.0.0.5")
        require_authorization("eng-001", "172.16.5.10")
        require_authorization("eng-001", "192.168.100.1")

    def test_authorization_at_exact_window_boundary(self):
        """start_utc == now should be valid (start_utc <= now is the check)."""
        now = _now()
        eng = make_engagement(
            start_utc=now - timedelta(seconds=1),
            end_utc=now + timedelta(hours=1),
        )
        register_engagement(eng)
        result = require_authorization("eng-001", "192.168.1.1")
        assert result is eng


# ── engagement_fingerprint ─────────────────────────────────────────────


class TestEngagementFingerprint:
    def test_returns_string(self):
        eng = make_engagement()
        fp = engagement_fingerprint(eng)
        assert isinstance(fp, str)

    def test_exactly_16_hex_characters(self):
        eng = make_engagement()
        fp = engagement_fingerprint(eng)
        assert len(fp) == 16
        assert all(c in "0123456789abcdef" for c in fp)

    def test_deterministic_same_inputs(self):
        eng = make_engagement()
        assert engagement_fingerprint(eng) == engagement_fingerprint(eng)

    def test_different_id_produces_different_fingerprint(self):
        eng1 = make_engagement(engagement_id="eng-001")
        eng2 = make_engagement(engagement_id="eng-002")
        assert engagement_fingerprint(eng1) != engagement_fingerprint(eng2)

    def test_different_authorized_by_produces_different_fingerprint(self):
        eng1 = make_engagement(authorized_by="alice@example.com")
        eng2 = make_engagement(authorized_by="bob@example.com")
        assert engagement_fingerprint(eng1) != engagement_fingerprint(eng2)

    def test_different_start_utc_produces_different_fingerprint(self):
        now = _now()
        eng1 = make_engagement(start_utc=now - timedelta(hours=1))
        eng2 = make_engagement(start_utc=now - timedelta(hours=2))
        assert engagement_fingerprint(eng1) != engagement_fingerprint(eng2)

    def test_different_end_utc_produces_different_fingerprint(self):
        now = _now()
        eng1 = make_engagement(end_utc=now + timedelta(hours=10))
        eng2 = make_engagement(end_utc=now + timedelta(hours=20))
        assert engagement_fingerprint(eng1) != engagement_fingerprint(eng2)

    def test_scope_does_not_affect_fingerprint(self):
        """Per the implementation, fingerprint only covers id, authorized_by, start_utc, end_utc."""
        now = _now()
        base = dict(
            engagement_id="eng-001",
            authorized_by="alice@example.com",
            start_utc=now - timedelta(hours=1),
            end_utc=now + timedelta(hours=1),
            rules_of_engagement="RoE",
        )
        eng1 = Engagement(scope=["10.0.0."], **base)
        eng2 = Engagement(scope=["192.168.1."], **base)
        assert engagement_fingerprint(eng1) == engagement_fingerprint(eng2)

    def test_teams_does_not_affect_fingerprint(self):
        now = _now()
        base = dict(
            engagement_id="eng-001",
            authorized_by="alice@example.com",
            start_utc=now - timedelta(hours=1),
            end_utc=now + timedelta(hours=1),
            rules_of_engagement="RoE",
            scope=["*"],
        )
        eng1 = Engagement(teams=["red"], **base)
        eng2 = Engagement(teams=["red", "purple", "osint"], **base)
        assert engagement_fingerprint(eng1) == engagement_fingerprint(eng2)

    def test_fingerprint_not_empty(self):
        eng = make_engagement()
        fp = engagement_fingerprint(eng)
        assert fp != ""
        assert fp != "0" * 16
