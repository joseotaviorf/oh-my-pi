"""
Execute Trino SQL with OAuth2 authentication.

This script wraps `trino-python-client` with capabilities tailored to
sandboxed environments (Cowork, CI runners, container without OS keyring,
shells with short timeouts):

1. `_FileTokenCache` - persists OAuth2 tokens to a JSON file on disk so that
   subsequent invocations of the script reuse the same access token instead of
   triggering a new browser-based OAuth dance every query. Default path is
   `${TARS_TOKEN_CACHE_FILE:-$PWD/.tars/oauth_tokens.json}`. The `$PWD/.tars/`
   default is Cowork-safe; users on a typical Mac who prefer a global token
   cache can set `TARS_TOKEN_CACHE_FILE=~/.cache/trino/tars_oauth_tokens.json`.

2. Two OAuth flows for warming up the cache:

   a) `--auth-only` (legacy) — runs `SELECT 1` and lets trino-python-client
      drive the OAuth2 dance synchronously. Requires a long-lived shell
      window (≥ 1–2 minutes) so the user can click the auth URL before the
      bearer's polling exits. **Does not work in Cowork-style sandboxes**
      where bash calls are capped at 45 s and stdout is delivered only after
      the call completes.

   b) `--init-oauth` + `--complete-oauth` (split flow) — fits any shell with
      a short timeout. Phase 1 makes a single unauthenticated request,
      extracts `x_redirect_server` (URL the user must click) and
      `x_token_server` (URL the client must poll) from the WWW-Authenticate
      header, and persists them to a state file. Phase 2, run **after** the
      user authenticates in their browser, polls the token endpoint and
      writes the resulting JWT to the file token cache in the format the
      bearer expects (`host@user` key, raw token string).

The default behaviour without `--external-auth` is unchanged.
"""
import argparse
import csv
import datetime as _dt
import json
import os
import re
import stat
import sys
import threading
import time
from typing import Optional
from urllib.parse import urlparse

import pandas as pd
from trino.auth import BasicAuthentication, OAuth2Authentication
from trino.dbapi import connect


# Hardcoded mapping of allowed Trino hosts → canonical statement-endpoint URL.
#
# This is the SSRF control surface (CWE-918). The pattern is dict-lookup with
# literal values: `dict.get(host)` returns one of the LITERAL strings declared
# below. The tainted `host` value (originating from argparse --host) only acts
# as a lookup key; the value handed to `requests.*` is a code constant, which
# is the canonical sanitizer pattern Snyk Code and similar dataflow analyzers
# recognize for CWE-918.
#
# `_KNOWN_TRINO_HOSTS` is derived from the keys for use in the defense-in-depth
# checks (`_ensure_known_trino_host`, `_ensure_known_trino_url`) and the inline
# guard in `complete_oauth`.
#
# To support a new Trino cluster, add a literal entry to this dict and open a
# PR — code review is the intended gate, not a runtime env var or regex
# override (both of which would be tainted-input sources from a static-analysis
# perspective).
_TRINO_STATEMENT_URLS = {
    "trino.apps.data-prd.habitat.zone": "https://trino.apps.data-prd.habitat.zone/v1/statement",
}

_KNOWN_TRINO_HOSTS = frozenset(_TRINO_STATEMENT_URLS.keys())


def _ensure_known_trino_host(host: str) -> None:
    """Raise ValueError if `host` is not in the hardcoded Trino allowlist.

    Defense-in-depth against SSRF: this is a local CLI and the operator types
    `--host` themselves, but constraining the value to known Trino hosts:
      - keeps a misconfigured `TRINO_HOST` env var from sending OAuth tokens or
        stray queries to the wrong endpoint (e.g. cloud metadata, an internal
        service, an attacker-controlled domain pasted from a phishing link);
      - silences the matching Snyk dataflow finding (CWE-918).
    """
    if host not in _KNOWN_TRINO_HOSTS:
        raise ValueError(
            f"Host {host!r} is not in the allowed Trino host list "
            f"({sorted(_KNOWN_TRINO_HOSTS)!r}). To add a new cluster, edit "
            f"_KNOWN_TRINO_HOSTS in execute_trino.py and open a PR."
        )


def _ensure_known_trino_url(url: str) -> None:
    """Raise ValueError if `url` is not http(s) on an allowlisted host.

    Used for URLs returned by the Trino server (e.g. OAuth redirect / poll
    URLs from the WWW-Authenticate header) before we make a request to them
    or surface them to the user.
    """
    parsed = urlparse(url)
    if parsed.scheme not in ("https", "http"):
        raise ValueError(f"URL {url!r} has invalid scheme: {parsed.scheme!r}")
    if parsed.hostname not in _KNOWN_TRINO_HOSTS:
        raise ValueError(
            f"URL {url!r} points at host {parsed.hostname!r}, which is not "
            f"in the allowed Trino host list "
            f"({sorted(_KNOWN_TRINO_HOSTS)!r})."
        )


def _default_token_cache_path() -> str:
    """Resolve the token cache path at call time.

    Order of precedence:
      1. `$TARS_TOKEN_CACHE_FILE` (user override; supports `~`).
      2. `$PWD/.tars/oauth_tokens.json` — Cowork-safe default. `$PWD` is the
         only directory we can guarantee is writable across sandboxes
         (`/tmp` and `~/.cache/` are commonly read-only in Cowork containers).

    Setting `TARS_TOKEN_CACHE_FILE=~/.cache/trino/tars_oauth_tokens.json`
    restores the pre-v5 behaviour of sharing tokens across projects on a
    machine where the home cache is writable (typical Mac).
    """
    override = os.environ.get("TARS_TOKEN_CACHE_FILE")
    if override:
        return os.path.expanduser(override)
    return os.path.join(os.getcwd(), ".tars", "oauth_tokens.json")


def _default_oauth_state_path() -> str:
    """Resolve the OAuth state path at call time. See `_default_token_cache_path`."""
    override = os.environ.get("TARS_OAUTH_STATE_FILE")
    if override:
        return os.path.expanduser(override)
    return os.path.join(os.getcwd(), ".tars", "trino_oauth_state.json")


# Headroom under typical sandbox bash limits (Cowork = 45 s).
DEFAULT_OAUTH_POLL_BUDGET_SECONDS = int(os.environ.get("TARS_OAUTH_POLL_BUDGET_S", "35"))


# ---------------------------------------------------------------------------
# Token cache
# ---------------------------------------------------------------------------

class _FileTokenCache:
    """OAuth2 token cache backed by a JSON file on disk.

    Implements the duck-typed interface expected by
    `trino.auth._OAuth2TokenBearer._token_cache`:
      - get_token_from_cache(key) -> Optional[str]
      - store_token_to_cache(key, token) -> None

    NOTE on the cache key: the bearer constructs keys as `host@user`, where
    `user` comes from the X-Trino-User header (or HEADER_ORIGINAL_USER).
    Writing tokens under a `host`-only key will be silently ignored. The
    `--complete-oauth` flow uses the same key shape on purpose.
    """

    def __init__(self, path: str):
        self._path = path
        self._lock = threading.Lock()

    def _read(self) -> dict:
        if not os.path.exists(self._path):
            return {}
        try:
            with open(self._path, "r", encoding="utf-8") as f:
                data = json.load(f)
            return data if isinstance(data, dict) else {}
        except (OSError, ValueError):
            return {}

    def _write(self, data: dict) -> None:
        directory = os.path.dirname(self._path)
        if directory:
            os.makedirs(directory, exist_ok=True)
        tmp_path = f"{self._path}.tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.chmod(tmp_path, stat.S_IRUSR | stat.S_IWUSR)
        os.replace(tmp_path, self._path)

    def get_token_from_cache(self, key):
        with self._lock:
            return self._read().get(str(key))

    def store_token_to_cache(self, key, token):
        with self._lock:
            data = self._read()
            data[str(key)] = token
            self._write(data)


def _build_oauth_auth(token_cache_path: str) -> OAuth2Authentication:
    auth = OAuth2Authentication()
    auth._bearer._token_cache = _FileTokenCache(token_cache_path)
    return auth


# ---------------------------------------------------------------------------
# Result serialization
# ---------------------------------------------------------------------------

def _to_jsonable(value):
    """Convert pandas / Python values into JSON-safe primitives.

    Fixes a long-standing bug where `date`, `time`, `Timedelta`, and similar
    types caused `json.dumps` to raise `TypeError: Object of type ... is not
    JSON serializable`, which left the output file empty.
    """
    if value is None:
        return None
    if isinstance(value, (str, int, float, bool)):
        # NaN/inf survive json.dumps with allow_nan=True (default), but we
        # could also coerce them here if strict JSON is required.
        return value
    if isinstance(value, (_dt.datetime, _dt.date, _dt.time)):
        return value.isoformat()
    if isinstance(value, _dt.timedelta):
        return value.total_seconds()
    if hasattr(value, "isoformat"):
        return value.isoformat()
    if isinstance(value, (bytes, bytearray, memoryview)):
        try:
            return bytes(value).decode("utf-8")
        except UnicodeDecodeError:
            return bytes(value).hex()
    if hasattr(value, "tolist"):
        return value.tolist()
    return str(value)


def _normalize_dataframe(df: "pd.DataFrame") -> list:
    """Convert a DataFrame to a list-of-lists with JSON-safe scalars."""
    out = []
    for record in df.itertuples(index=False, name=None):
        out.append([_to_jsonable(v) for v in record])
    return out


def _write_csv(path: str, columns, rows) -> None:
    """Write rows (list of lists) to a CSV file at `path` with a header row.

    Values are passed through `_to_jsonable` first so that `date`, `datetime`,
    `time`, `bytes`, etc. become CSV-safe strings instead of Python repr.
    Creates parent directory on demand and atomically replaces the target.
    """
    directory = os.path.dirname(path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    tmp_path = f"{path}.tmp"
    with open(tmp_path, "w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh, quoting=csv.QUOTE_MINIMAL)
        writer.writerow(list(columns))
        for row in rows:
            writer.writerow([_to_jsonable(v) for v in row])
    os.replace(tmp_path, path)


# ---------------------------------------------------------------------------
# Query execution
# ---------------------------------------------------------------------------

PREVIEW_ROWS = 10


def run_query(query, host, port, user, catalog=None, schema=None,
              password=None, external_auth=False, token_cache_path=None,
              csv_output_path=None):
    """Execute a Trino query.

    When `csv_output_path` is set, the full result rows are written as CSV to
    that path and the returned JSON envelope contains only a `preview` (first
    `PREVIEW_ROWS` rows) plus `csv_file`, instead of the full `data` array.
    This keeps stdout small for large result sets (the LIMIT default is 100000)
    while still giving the agent enough rows to render a Markdown preview.

    On error, no CSV file is created — the envelope only contains
    `status: "error"` and `message`. Callers should persist the error envelope
    to a sidecar (e.g. `<file>.error.json`) if forensic logging is desired.
    """
    try:
        if external_auth:
            auth = _build_oauth_auth(token_cache_path or _default_token_cache_path())
        else:
            auth = BasicAuthentication(user, password) if password else None

        conn = connect(
            host=host,
            port=port,
            user=user,
            catalog=catalog,
            schema=schema,
            http_scheme='https' if port == 443 else 'http',
            auth=auth,
        )

        df = pd.read_sql_query(query, conn)
        columns = list(df.columns)
        rows = _normalize_dataframe(df)

        if csv_output_path:
            _write_csv(csv_output_path, columns, rows)
            return {
                "status": "success",
                "columns": columns,
                "preview": rows[:PREVIEW_ROWS],
                "count": len(rows),
                "csv_file": csv_output_path,
            }

        return {
            "status": "success",
            "columns": columns,
            "data": rows,
            "count": len(rows),
        }

    except Exception as e:
        return {"status": "error", "message": str(e)}


# ---------------------------------------------------------------------------
# Split OAuth flow (Cowork-friendly)
# ---------------------------------------------------------------------------

_BEARER_FIELD_RE = re.compile(r'(\w+)="([^"]+)"')


def _save_oauth_state(state_path: str, state: dict) -> None:
    directory = os.path.dirname(state_path)
    if directory:
        os.makedirs(directory, exist_ok=True)
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    os.chmod(state_path, stat.S_IRUSR | stat.S_IWUSR)


def _load_oauth_state(state_path: str) -> Optional[dict]:
    if not os.path.exists(state_path):
        return None
    try:
        with open(state_path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def init_oauth(host: str, port: int, user: str, state_path: str) -> dict:
    """Phase 1 of the split OAuth flow.

    Sends a single unauthenticated POST to /v1/statement and parses the
    Bearer challenge from the WWW-Authenticate header. Returns the redirect
    URL (to be shown to the user) and persists both URLs to `state_path` so
    that `complete_oauth` can resume the flow in a separate shell call.
    """
    import requests  # local import keeps the simple --query path lightweight

    # SSRF guard via dict-lookup with literal values (CWE-918): `host` only
    # acts as a lookup key, and the URL handed to `requests.post` originates
    # from the literal strings in `_TRINO_STATEMENT_URLS` (source-code
    # constants), not from argparse --host. This is the canonical sanitizer
    # pattern that Snyk Code's taint tracker recognizes.
    statement_url = _TRINO_STATEMENT_URLS.get(host)
    if statement_url is None:
        return {
            "status": "error",
            "message": f"Host {host!r} is not in the allowed Trino host list.",
        }

    # Non-default ports (local dev / port-forward) re-derive the URL from
    # `urlparse(statement_url)`: `parts.hostname` and `parts.path` come from
    # the literal value above, and `int(port)` makes the integer cast explicit
    # so the rebuilt URL has no tainted-string component.
    if port != 443:
        parts = urlparse(statement_url)
        statement_url = f"http://{parts.hostname}:{int(port)}{parts.path}"

    headers = {"X-Trino-User": user, "Content-Type": "text/plain"}
    try:
        r = requests.post(
            statement_url,
            data="SELECT 1",
            headers=headers,
            allow_redirects=False,
            timeout=15,
        )
    except requests.RequestException as e:
        return {"status": "error", "message": f"Network error contacting Trino: {e}"}

    if r.status_code != 401:
        return {
            "status": "error",
            "message": (f"Expected HTTP 401 with Bearer challenge, got "
                        f"{r.status_code}. Body: {r.text[:300]}"),
        }

    # The WWW-Authenticate value mixes Basic + multiple Bearer challenges
    # separated by ", ", and the Bearer challenge fields themselves are also
    # comma-separated. Splitting by ", " corrupts the value, so we extract
    # the two fields we care about directly via regex on the full header.
    raw_header = r.headers.get("WWW-Authenticate", "")
    fields = dict(_BEARER_FIELD_RE.findall(raw_header))
    redirect = fields.get("x_redirect_server")
    token_server = fields.get("x_token_server")
    if not redirect or not token_server:
        return {
            "status": "error",
            "message": f"Could not parse Bearer challenge. Header: {raw_header}",
        }

    # The Trino server controls these URLs. Constrain them to the same allowlist
    # the operator's --host went through, so a misconfigured / compromised
    # upstream cannot redirect the OAuth dance to an arbitrary endpoint.
    try:
        _ensure_known_trino_url(redirect)
        _ensure_known_trino_url(token_server)
    except ValueError as e:
        return {
            "status": "error",
            "message": f"Bearer challenge returned an untrusted URL: {e}",
        }

    state = {
        "host": host,
        "port": port,
        "user": user,
        "redirect_url": redirect,
        "poll_url": token_server,
        "issued_at": _dt.datetime.utcnow().replace(microsecond=0).isoformat() + "Z",
    }
    _save_oauth_state(state_path, state)
    return {
        "status": "success",
        "redirect_url": redirect,
        "state_file": state_path,
        "instructions": "Open redirect_url in a browser, complete the SSO flow, "
                        "then run --complete-oauth.",
    }


def complete_oauth(state_path: str, token_cache_path: str,
                   poll_budget_seconds: int = DEFAULT_OAUTH_POLL_BUDGET_SECONDS) -> dict:
    """Phase 2 of the split OAuth flow.

    Polls the `x_token_server` URL persisted by `init_oauth` until the Trino
    server returns the access token. Writes the token to the file token cache
    using the same `host@user` key the trino-python-client bearer expects.
    """
    import requests

    state = _load_oauth_state(state_path)
    if state is None:
        return {
            "status": "error",
            "message": f"OAuth state file not found at {state_path}. "
                       f"Run --init-oauth first.",
        }

    host = state["host"]
    user = state["user"]
    poll_url = state["poll_url"]

    try:
        _ensure_known_trino_host(host)
        _ensure_known_trino_url(poll_url)
    except ValueError as e:
        return {
            "status": "error",
            "message": f"OAuth state references an untrusted host/URL: {e}",
        }

    # Re-parse poll_url and check the hostname against the literal allowlist
    # immediately before the request — the inline `x in frozenset({...})`
    # pattern Snyk Code recognizes as an SSRF sanitizer (CWE-918).
    poll_host = urlparse(poll_url).hostname
    if poll_host not in _KNOWN_TRINO_HOSTS:
        return {
            "status": "error",
            "message": (
                f"poll_url {poll_url!r} points at host {poll_host!r}, which is "
                f"not in the allowed Trino host list."
            ),
        }

    sess = requests.Session()
    sess.headers["User-Agent"] = "tars-cowork/1.0"

    deadline = time.time() + poll_budget_seconds
    last_status: Optional[int] = None
    while time.time() < deadline:
        try:
            r = sess.get(poll_url, timeout=15)
        except requests.exceptions.ReadTimeout:
            continue
        except requests.RequestException as e:
            return {"status": "error", "message": f"Network error during poll: {e}"}

        last_status = r.status_code
        if r.status_code == 200:
            text = r.text.strip()
            if not text:
                # Server is still waiting on the user; keep polling.
                time.sleep(1)
                continue
            token: Optional[str] = None
            still_waiting = False
            try:
                obj = json.loads(text)
                token = obj.get("token") or obj.get("access_token")
                # When the user hasn't authenticated yet, the server returns
                # 200 with a body like {"nextUri": "..."} — that's a "keep
                # polling" signal, not an error.
                if token is None and "nextUri" in obj:
                    still_waiting = True
                    new_url = obj.get("nextUri")
                    if new_url:
                        poll_url = new_url
            except json.JSONDecodeError:
                token = text  # some Trino versions return the bare JWT

            if still_waiting:
                time.sleep(1)
                continue
            if not token:
                return {
                    "status": "error",
                    "message": f"Token endpoint returned 200 but no token: {text[:200]}",
                }

            cache = _FileTokenCache(token_cache_path)
            cache.store_token_to_cache(f"{host}@{user}", token)
            return {
                "status": "success",
                "token_cache_file": token_cache_path,
                "cache_key": f"{host}@{user}",
                "token_preview": token[:24] + "...",
            }
        elif r.status_code == 401:
            time.sleep(1)
            continue
        else:
            return {
                "status": "error",
                "message": f"Token endpoint returned {r.status_code}: {r.text[:200]}",
            }

    return {
        "status": "timeout",
        "message": (f"Polling exceeded {poll_budget_seconds}s budget. "
                    f"Re-run --complete-oauth after the user authenticates."),
        "last_http_status": last_status,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    parser.add_argument("--query")
    parser.add_argument("--host")
    parser.add_argument("--port", type=int, default=443)
    parser.add_argument("--user")
    parser.add_argument(
        "--catalog",
        default=None,
        help=(
            "Trino catalog. Precedence: --catalog flag > $TRINO_CATALOG env "
            "var > 'delta' (default). At QuintoAndar, 'delta' is the modern "
            "Trino-managed catalog and the canonical choice for analytics. "
            "Use 'hive' only when the user explicitly asks for the legacy "
            "Glue/Athena catalog. The non-None default eliminates "
            "MISSING_CATALOG_NAME errors and the agent-side branching they "
            "trigger."
        ),
    )
    parser.add_argument("--schema")
    parser.add_argument("--password")
    parser.add_argument("--external-auth", action="store_true")
    parser.add_argument(
        "--auth-only",
        action="store_true",
        help=("LEGACY: drives the trino-python-client OAuth2 dance "
              "synchronously. Requires a long-lived shell (>~1 min). For "
              "Cowork or short-timeout shells, prefer --init-oauth + "
              "--complete-oauth."),
    )
    parser.add_argument(
        "--init-oauth",
        action="store_true",
        help=("Phase 1 of split OAuth flow. Returns the redirect URL the "
              "user must open in a browser, and saves polling state to "
              "$TARS_OAUTH_STATE_FILE (default $PWD/.tars/trino_oauth_state.json)."),
    )
    parser.add_argument(
        "--complete-oauth",
        action="store_true",
        help=("Phase 2 of split OAuth flow. Run AFTER the user has clicked "
              "the redirect URL. Polls the token endpoint and writes the "
              "JWT into the file token cache with the correct host@user "
              "key."),
    )
    parser.add_argument(
        "--oauth-state-file",
        default=None,
        help=("Path to the JSON file used by --init-oauth/--complete-oauth "
              "to share state. Defaults to $TARS_OAUTH_STATE_FILE or "
              "$PWD/.tars/trino_oauth_state.json."),
    )
    parser.add_argument(
        "--oauth-poll-budget-seconds",
        type=int,
        default=DEFAULT_OAUTH_POLL_BUDGET_SECONDS,
        help=("Maximum seconds --complete-oauth will poll for the token. "
              "Default 35 (fits a 45 s bash budget). Increase if your shell "
              "has more headroom."),
    )
    parser.add_argument(
        "--token-cache-file",
        default=None,
        help=("Path to the JSON file used to persist OAuth2 tokens between "
              "invocations. Defaults to $TARS_TOKEN_CACHE_FILE or "
              "$PWD/.tars/oauth_tokens.json."),
    )
    parser.add_argument(
        "--csv-output",
        default=None,
        help=("If set, write the full query result rows as CSV to PATH "
              "(header row + data). Stdout JSON omits the bulky 'data' array "
              "and instead returns 'preview' (first 10 rows) plus 'csv_file'. "
              "Recommended for the default LIMIT 100000 result size — keeps "
              "stdout small. On error, no CSV file is created."),
    )
    return parser


def main(argv=None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    host = args.host or os.environ.get("TRINO_HOST")
    user = args.user or os.environ.get("TRINO_USER") or "quinto-agent"
    token_cache_path = args.token_cache_file or _default_token_cache_path()
    state_path = args.oauth_state_file or _default_oauth_state_path()
    # Catalog resolution: flag > env > 'delta' default. Eliminates the
    # MISSING_CATALOG_NAME / "hive vs delta" branch that bit the agent in v5.
    catalog = args.catalog or os.environ.get("TRINO_CATALOG") or "delta"

    if not host:
        print(json.dumps({
            "status": "error",
            "message": "Trino host not provided. Set TRINO_HOST or pass --host.",
        }))
        return 1

    try:
        _ensure_known_trino_host(host)
    except ValueError as e:
        print(json.dumps({"status": "error", "message": str(e)}))
        return 1

    # Mutually exclusive flow selectors.
    flow_flags = sum(bool(x) for x in (args.auth_only, args.init_oauth, args.complete_oauth))
    if flow_flags > 1:
        print(json.dumps({
            "status": "error",
            "message": "--auth-only, --init-oauth, --complete-oauth are mutually exclusive.",
        }))
        return 1

    if args.init_oauth:
        res = init_oauth(host, args.port, user, state_path)
        print(json.dumps(res))
        return 0 if res.get("status") == "success" else 1

    if args.complete_oauth:
        res = complete_oauth(state_path, token_cache_path, args.oauth_poll_budget_seconds)
        print(json.dumps(res))
        return 0 if res.get("status") == "success" else 1

    if args.auth_only:
        if not args.external_auth:
            print(json.dumps({
                "status": "error",
                "message": "--auth-only requires --external-auth.",
            }))
            return 1
        res = run_query(
            "SELECT 1 AS auth_warmup",
            host, args.port, user, catalog, args.schema,
            None, True, token_cache_path,
        )
        if res.get("status") == "success":
            print(json.dumps({
                "status": "success",
                "message": "OAuth2 token cached.",
                "token_cache_file": token_cache_path,
            }))
            return 0
        print(json.dumps(res))
        return 1

    if not args.query:
        print(json.dumps({
            "status": "error",
            "message": ("--query is required (unless using --auth-only, "
                        "--init-oauth, or --complete-oauth)."),
        }))
        return 1

    res = run_query(
        args.query, host, args.port, user, catalog, args.schema,
        args.password, args.external_auth, token_cache_path,
        args.csv_output,
    )
    print(json.dumps(res))
    return 0 if res.get("status") == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
