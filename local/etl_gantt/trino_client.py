"""Trino connection: SSO bootstrap, then query session as JWT identity."""

from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Any

import pandas as pd
from trino.auth import JWTAuthentication, OAuth2Authentication
from trino.dbapi import connect

from identity import trino_user_from_oauth_token

BOOTSTRAP_USER = "_oauth_bootstrap"
DEFAULT_HOST = "trino.apps.data-prd.habitat.zone"
DEFAULT_PORT = 443
DEFAULT_CATALOG = "hive"
QUERY_SOURCE = "etl_gantt"
QUERY_MAX_RUN_TIME = "5m"
_ALLOWED_HOST_RE = re.compile(
    r"^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?"
    r"(?:\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*"
    r"\.habitat\.zone$"
)


class TrinoHostError(ValueError):
    """Raised when TRINO_HOST is missing or not an allowed hostname."""


@dataclass(frozen=True)
class TrinoSession:
    connection: Any
    user: str
    host: str


def trino_host() -> str:
    raw = os.environ.get("TRINO_HOST", DEFAULT_HOST).strip()
    host = raw.lower()
    if not host or "://" in host or "/" in host or ":" in host:
        raise TrinoHostError(
            f"TRINO_HOST {raw!r} is not an allowed Trino hostname. "
            f"Use a *.habitat.zone host (default {DEFAULT_HOST})."
        )
    if not _ALLOWED_HOST_RE.fullmatch(host):
        raise TrinoHostError(
            f"TRINO_HOST {raw!r} is not an allowed Trino hostname. "
            f"Use a *.habitat.zone host (default {DEFAULT_HOST})."
        )
    return host


def _cache_key(host: str, user: str) -> str:
    return f"{host}@{user}"


def read_cached_oauth_token(host: str, user: str) -> str:
    import keyring

    key = _cache_key(host, user)
    token = keyring.get_password(key, "token")
    if not token:
        raise RuntimeError(
            f"No OAuth token in keyring for {key}. Complete Trino SSO in the browser."
        )
    return token


def _connect(*, user: str, auth: Any, host: str):
    return connect(
        host=host,
        port=DEFAULT_PORT,
        user=user,
        catalog=DEFAULT_CATALOG,
        http_scheme="https",
        auth=auth,
        source=QUERY_SOURCE,
        session_properties={"query_max_run_time": QUERY_MAX_RUN_TIME},
    )


def _run_select_one(connection: Any) -> None:
    cursor = connection.cursor()
    cursor.execute("SELECT 1")
    cursor.fetchall()


def _trigger_sso(host: str) -> str:
    """Force the OAuth round-trip so the token lands in the keyring cache.

    The statement itself is expected to fail: the bootstrap session user is not
    the SSO principal, so Trino denies it as impersonation *after* authenticating.
    That denial is expected and shows up in Trino audit logs; it is not an
    attack. Only a missing token means SSO actually failed.
    """
    bootstrap = _connect(
        user=BOOTSTRAP_USER,
        auth=OAuth2Authentication(),
        host=host,
    )
    statement_error: Exception | None = None
    try:
        _run_select_one(bootstrap)
    except Exception as exc:
        statement_error = exc
    finally:
        bootstrap.close()

    try:
        return read_cached_oauth_token(host, BOOTSTRAP_USER)
    except RuntimeError as exc:
        if statement_error is not None:
            raise RuntimeError(f"{exc} Trino reported: {statement_error}") from exc
        raise


def connect_for_queries() -> TrinoSession:
    """Open SSO, derive user from the JWT, reconnect for queries."""
    host = trino_host()
    token = _trigger_sso(host)
    user = trino_user_from_oauth_token(token)
    connection = _connect(
        user=user,
        auth=JWTAuthentication(token),
        host=host,
    )
    return TrinoSession(connection=connection, user=user, host=host)


def read_sql(connection: Any, sql: str) -> pd.DataFrame:
    """Run SQL and return a DataFrame.

    Built from the cursor rather than pandas.read_sql_query, which warns for
    non-SQLAlchemy DBAPI connections.
    """
    cursor = connection.cursor()
    cursor.execute(sql)
    rows = cursor.fetchall()
    columns = [column[0] for column in cursor.description or []]
    return pd.DataFrame(rows, columns=columns)
