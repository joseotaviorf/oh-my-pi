from unittest.mock import MagicMock

import pytest
from trino.auth import JWTAuthentication, OAuth2Authentication

import trino_client
from tests.jwt_util import make_jwt


def test_two_step_connect_without_trino_user(monkeypatch):
    token = make_jwt({"email": "ada@quintoandar.com.br"})
    calls: list[dict] = []

    def fake_connect(**kwargs):
        calls.append(kwargs)
        conn = MagicMock()
        cursor = MagicMock()
        conn.cursor.return_value = cursor
        return conn

    monkeypatch.delenv("TRINO_USER", raising=False)
    monkeypatch.delenv("TRINO_HOST", raising=False)
    monkeypatch.setattr(trino_client, "connect", fake_connect)
    monkeypatch.setattr(
        trino_client,
        "read_cached_oauth_token",
        lambda host, user: token,
    )

    session = trino_client.connect_for_queries()

    assert session.user == "ada@quintoandar.com.br"
    assert session.host == trino_client.DEFAULT_HOST
    assert len(calls) == 2

    bootstrap, query = calls
    assert bootstrap["user"] == trino_client.BOOTSTRAP_USER
    assert bootstrap["host"] == trino_client.DEFAULT_HOST
    assert bootstrap["port"] == trino_client.DEFAULT_PORT
    assert bootstrap["catalog"] == trino_client.DEFAULT_CATALOG
    assert bootstrap["http_scheme"] == "https"
    assert bootstrap["source"] == trino_client.QUERY_SOURCE
    assert bootstrap["session_properties"] == {
        "query_max_run_time": trino_client.QUERY_MAX_RUN_TIME
    }
    assert isinstance(bootstrap["auth"], OAuth2Authentication)

    assert query["user"] == "ada@quintoandar.com.br"
    assert query["host"] == trino_client.DEFAULT_HOST
    assert query["port"] == 443
    assert query["catalog"] == "hive"
    assert query["http_scheme"] == "https"
    assert query["source"] == "etl_gantt"
    assert query["session_properties"] == {"query_max_run_time": "5m"}
    assert isinstance(query["auth"], JWTAuthentication)
    assert query["auth"].token == token


def test_bootstrap_impersonation_denial_is_tolerated(monkeypatch):
    token = make_jwt({"email": "ada@quintoandar.com.br"})
    calls: list[dict] = []

    def fake_connect(**kwargs):
        calls.append(kwargs)
        conn = MagicMock()
        if kwargs["user"] == trino_client.BOOTSTRAP_USER:
            conn.cursor.return_value.execute.side_effect = RuntimeError(
                "Access Denied: User ada@quintoandar.com cannot impersonate user "
                "_oauth_bootstrap"
            )
        return conn

    monkeypatch.delenv("TRINO_HOST", raising=False)
    monkeypatch.setattr(trino_client, "connect", fake_connect)
    monkeypatch.setattr(
        trino_client,
        "read_cached_oauth_token",
        lambda host, user: token,
    )

    session = trino_client.connect_for_queries()

    assert session.user == "ada@quintoandar.com.br"
    assert len(calls) == 2
    assert calls[1]["user"] == "ada@quintoandar.com.br"


def test_missing_token_reports_underlying_trino_error(monkeypatch):
    def fake_connect(**kwargs):
        conn = MagicMock()
        conn.cursor.return_value.execute.side_effect = RuntimeError("boom from trino")
        return conn

    def no_token(host, user):
        raise RuntimeError("No OAuth token in keyring.")

    monkeypatch.delenv("TRINO_HOST", raising=False)
    monkeypatch.setattr(trino_client, "connect", fake_connect)
    monkeypatch.setattr(trino_client, "read_cached_oauth_token", no_token)

    with pytest.raises(RuntimeError, match="boom from trino"):
        trino_client.connect_for_queries()


def test_trino_host_override_allows_habitat_zone(monkeypatch):
    monkeypatch.setenv("TRINO_HOST", "trino.apps.data-forno.habitat.zone")
    assert trino_client.trino_host() == "trino.apps.data-forno.habitat.zone"


def test_trino_host_rejects_non_habitat_zone(monkeypatch):
    monkeypatch.setenv("TRINO_HOST", "trino.example.internal")
    with pytest.raises(trino_client.TrinoHostError, match="habitat.zone"):
        trino_client.trino_host()


@pytest.mark.parametrize(
    "host",
    [
        "https://trino.apps.data-prd.habitat.zone",
        "trino.apps.data-prd.habitat.zone:443",
        "trino.apps.data-prd.habitat.zone/v1",
        "evil.habitat.zone.attacker.example",
        "habitat.zone",
    ],
)
def test_trino_host_rejects_schemes_ports_and_suffix_spoofs(monkeypatch, host):
    monkeypatch.setenv("TRINO_HOST", host)
    with pytest.raises(trino_client.TrinoHostError):
        trino_client.trino_host()
