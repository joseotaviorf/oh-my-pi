#!/usr/bin/env python3
"""Launch Inspect View against archived tars-evals logs on S3.

Obtains temporary AWS credentials via QLI (ConsoleMe), then starts a
loopback-only Inspect View server that reads ``.eval`` logs directly from
``s3://`` — no sync-to-disk step.

Usage:
    uv run python scripts/view_inspect_logs_s3.py --list
    uv run python scripts/view_inspect_logs_s3.py \\
        --log-dir s3://5a-tars-prod-data/evals/inspect/2026/08/07/pr-26512/pipeline-89418
    make inspect-view-s3 S3_URI=s3://5a-tars-prod-data/evals/inspect/...

Open http://127.0.0.1:7575 after the server starts.

The S3 URI is validated and passed to Inspect's Python ``view()`` API
in-process (loopback bind only). Credentials are parsed from
``qli aws export`` stdout, applied only for the duration of the viewer, and
never printed or written to disk.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from collections.abc import Mapping
from typing import Any, Callable

DEFAULT_BUCKET = "5a-tars-prod-data"
DEFAULT_PREFIX_ROOT = "evals/inspect"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 7575
DEFAULT_REGION = "us-east-1"

# S3 URIs may only contain characters safe as a filesystem path token.
_S3_URI_RE = re.compile(r"^s3://[a-z0-9][a-z0-9.\-]{1,61}[a-z0-9](/[A-Za-z0-9._\-/=]*)?$")
_ROLE_ARN_RE = re.compile(
    r"^arn:aws:iam::\d{12}:role/[A-Za-z0-9+=,.@_\-/]+$"
)

# Bash-style export lines from ``qli aws export --shell bash``.
_EXPORT_LINE_RE = re.compile(
    r"^\s*(?:export\s+)?(?P<key>AWS_[A-Z0-9_]+)=(?P<value>.*)\s*$"
)
_REQUIRED_AWS_KEYS = ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY")
_ALLOWED_AWS_KEYS = frozenset(
    {
        "AWS_ACCESS_KEY_ID",
        "AWS_SECRET_ACCESS_KEY",
        "AWS_SESSION_TOKEN",
        "AWS_DEFAULT_REGION",
        "AWS_REGION",
        "AWS_SECURITY_TOKEN",
    }
)


class ViewConfigError(ValueError):
    """Invalid CLI arguments or credential-export payload."""


def default_log_dir(
    *,
    bucket: str = DEFAULT_BUCKET,
    prefix_root: str = DEFAULT_PREFIX_ROOT,
) -> str:
    """Return the default archive root URI."""
    return f"s3://{bucket.rstrip('/')}/{prefix_root.strip('/')}"


def split_s3_uri(uri: str) -> tuple[str, str]:
    """Split a validated ``s3://bucket/key`` URI into ``(bucket, key)``."""
    without_scheme = uri[len("s3://") :]
    bucket, _, key = without_scheme.partition("/")
    return bucket, key


def validate_s3_uri(uri: str) -> str:
    """Require a non-empty, character-safe ``s3://bucket/...`` URI."""
    cleaned = (uri or "").strip().rstrip("/")
    if not cleaned.startswith("s3://"):
        raise ViewConfigError(
            f"log-dir must be an s3:// URI, got: {uri!r}. "
            f"Example: {default_log_dir()}"
        )
    without_scheme = cleaned[len("s3://") :]
    bucket, _, _key = without_scheme.partition("/")
    if not bucket:
        raise ViewConfigError(f"log-dir is missing a bucket name: {uri!r}")
    match = _S3_URI_RE.fullmatch(cleaned)
    if match is None:
        raise ViewConfigError(
            "log-dir contains unsupported characters. "
            "Allowed: s3://bucket/key with alphanumerics, ., _, -, /, ="
        )
    # Return the regex match (not the raw input) so only allow-listed bytes
    # reach downstream consumers / child env vars.
    return match.group(0)


def validate_role_arn(role_arn: str | None) -> str | None:
    """Return a cleaned role ARN, or None when unset."""
    cleaned = (role_arn or "").strip()
    if not cleaned:
        return None
    match = _ROLE_ARN_RE.fullmatch(cleaned)
    if match is None:
        raise ViewConfigError(
            "role-arn must look like "
            "arn:aws:iam::123456789012:role/RoleName"
        )
    return match.group(0)


def validate_port(port: int) -> int:
    if not (1 <= port <= 65535):
        raise ViewConfigError(f"port must be between 1 and 65535, got: {port}")
    return port


def _strip_shell_quotes(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1]
    return value


def parse_qli_export_output(stdout: str) -> dict[str, str]:
    """Extract AWS_* assignments from bash ``export`` lines.

    Only allowlisted credential keys are kept. Unknown ``AWS_*`` keys and
    non-export noise are ignored. Does not evaluate shell syntax.
    """
    credentials: dict[str, str] = {}
    for raw_line in stdout.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = _EXPORT_LINE_RE.match(line)
        if match is None:
            continue
        key = match.group("key")
        if key not in _ALLOWED_AWS_KEYS:
            continue
        credentials[key] = _strip_shell_quotes(match.group("value"))

    missing = [key for key in _REQUIRED_AWS_KEYS if not credentials.get(key)]
    if missing:
        raise ViewConfigError(
            "qli aws export did not yield required credential field(s): "
            + ", ".join(missing)
        )
    return credentials


def build_qli_export_command(role_arn: str | None = None) -> list[str]:
    """Build the ``qli aws export`` argv (role optional for interactive pick)."""
    command = ["qli", "aws", "export", "--shell", "bash"]
    # role_arn must already have passed validate_role_arn when supplied.
    if role_arn:
        command.append(role_arn)
    return command


def _run_qli_export_subprocess(
    command: list[str],
    *,
    interactive: bool,
    run: Callable[..., subprocess.CompletedProcess[str]],
) -> subprocess.CompletedProcess[str]:
    """Run ``qli aws export``; inherit the TTY when role selection is interactive."""
    if interactive:
        # Role pickers write prompts to the terminal. capture_output=True hides
        # them and can hang; capture export lines from stdout only.
        return run(
            command,
            stdin=None,
            stdout=subprocess.PIPE,
            stderr=None,
            text=True,
            check=False,
        )
    return run(
        command,
        capture_output=True,
        text=True,
        check=False,
    )


def fetch_qli_credentials(
    *,
    role_arn: str | None = None,
    run: Callable[..., subprocess.CompletedProcess[str]] = subprocess.run,
) -> dict[str, str]:
    """Call QLI and return temporary AWS credentials for the Inspect viewer."""
    if shutil.which("qli") is None:
        raise ViewConfigError(
            "qli not found on PATH. Install/authenticate QLI, then retry. "
            "ConsoleMe: https://consoleme.sre.quintoandar.com.br/"
        )

    safe_role = validate_role_arn(role_arn)
    interactive = safe_role is None
    if interactive and not sys.stdin.isatty():
        raise ViewConfigError(
            "QLI interactive role selection requires a TTY. "
            "Pass --role-arn (or set TARS_EVAL_S3_ROLE_ARN), or use "
            "--use-ambient-credentials when credentials are already exported."
        )

    command = build_qli_export_command(safe_role)
    try:
        completed = _run_qli_export_subprocess(
            command,
            interactive=interactive,
            run=run,
        )
    except OSError as error:
        raise ViewConfigError(f"failed to run qli aws export: {error}") from error

    if completed.returncode != 0:
        detail = (completed.stderr or completed.stdout or "").strip()
        # Never echo raw stdout — it may contain credential material on partial success.
        safe_detail = detail if "AWS_" not in detail else "(redacted: contained AWS_*)"
        raise ViewConfigError(
            f"qli aws export failed (exit {completed.returncode})"
            + (f": {safe_detail}" if safe_detail else "")
            + ". Authenticate via ConsoleMe "
            "(https://consoleme.sre.quintoandar.com.br/) and retry."
        )

    return parse_qli_export_output(completed.stdout or "")


def _boto3_client(credentials: Mapping[str, str] | None = None):
    """Build a boto3 S3 client, optionally from temporary credentials."""
    import boto3

    if not credentials:
        return boto3.client("s3", region_name=DEFAULT_REGION)
    return boto3.client(
        "s3",
        region_name=credentials.get("AWS_DEFAULT_REGION")
        or credentials.get("AWS_REGION")
        or DEFAULT_REGION,
        aws_access_key_id=credentials["AWS_ACCESS_KEY_ID"],
        aws_secret_access_key=credentials["AWS_SECRET_ACCESS_KEY"],
        aws_session_token=credentials.get("AWS_SESSION_TOKEN"),
    )


def prefix_has_objects(
    *,
    log_dir: str,
    credentials: Mapping[str, str] | None = None,
    s3_client=None,
) -> bool:
    """Return True when ``log_dir`` has at least one object under its prefix."""
    bucket, key = split_s3_uri(log_dir)
    prefix = f"{key.rstrip('/')}/" if key else ""
    client = s3_client or _boto3_client(credentials)
    response = client.list_objects_v2(Bucket=bucket, Prefix=prefix, MaxKeys=1)
    return bool(response.get("Contents") or response.get("CommonPrefixes"))


def list_child_prefixes(
    *,
    log_dir: str,
    credentials: Mapping[str, str] | None = None,
    s3_client=None,
    max_keys: int | None = None,
) -> list[str]:
    """List immediate child prefixes under ``log_dir`` as ``s3://`` URIs.

    Follows ``list_objects_v2`` pagination so prefixes past the first page
    are not dropped. ``max_keys`` caps how many URIs to return (used for
    nearby-prefix suggestions); ``None`` collects every child prefix.
    """
    bucket, key = split_s3_uri(log_dir)
    prefix = f"{key.rstrip('/')}/" if key else ""
    client = s3_client or _boto3_client(credentials)
    uris: list[str] = []
    continuation_token: str | None = None
    while True:
        request: dict[str, Any] = {
            "Bucket": bucket,
            "Prefix": prefix,
            "Delimiter": "/",
        }
        if continuation_token:
            request["ContinuationToken"] = continuation_token
        if max_keys is not None:
            remaining = max_keys - len(uris)
            if remaining <= 0:
                break
            request["MaxKeys"] = remaining
        response = client.list_objects_v2(**request)
        for entry in response.get("CommonPrefixes") or []:
            child = entry.get("Prefix") or ""
            if child:
                uris.append(f"s3://{bucket}/{child.rstrip('/')}")
                if max_keys is not None and len(uris) >= max_keys:
                    return uris
        if not response.get("IsTruncated"):
            break
        continuation_token = response.get("NextContinuationToken")
        if not continuation_token:
            break
    return uris


def ensure_log_dir_readable(
    *,
    log_dir: str,
    credentials: Mapping[str, str] | None = None,
    s3_client=None,
) -> None:
    """Fail closed with a helpful message when the archive prefix is empty/missing.

    Inspect View calls ``fs.info(log_dir)`` and will also attempt ``mkdir`` when
    the path is missing — that surfaces as a raw ``FileNotFoundError`` for
    placeholders / typos. Prefer a clear preflight error instead.
    """
    try:
        found = prefix_has_objects(
            log_dir=log_dir,
            credentials=credentials,
            s3_client=s3_client,
        )
    except Exception as error:  # noqa: BLE001 — surface any AWS/client failure
        raise ViewConfigError(
            f"failed to list {log_dir}: {error}. "
            "Check the role can read the bucket, then retry."
        ) from error

    if found:
        return

    parent = log_dir.rsplit("/", 1)[0] if "/" in log_dir[len("s3://") :] else log_dir
    suggestions: list[str] = []
    try:
        suggestions = list_child_prefixes(
            log_dir=parent,
            credentials=credentials,
            s3_client=s3_client,
            max_keys=10,
        )
    except Exception:  # noqa: BLE001 — suggestions are best-effort
        suggestions = []

    lines = [
        f"No objects found under {log_dir}.",
        "That usually means the PR/pipeline prefix is wrong or not uploaded yet.",
        "List runs with: uv run python scripts/view_inspect_logs_s3.py --list",
    ]
    if suggestions:
        lines.append(f"Nearby prefixes under {parent}:")
        lines.extend(f"  - {uri}" for uri in suggestions)
    raise ViewConfigError("\n".join(lines))


def _apply_env(updates: Mapping[str, str]) -> dict[str, str | None]:
    """Set env keys; return prior values (``None`` if previously unset)."""
    previous: dict[str, str | None] = {}
    for key, value in updates.items():
        previous[key] = os.environ.get(key)
        os.environ[key] = value
    return previous


def _restore_env(previous: Mapping[str, str | None]) -> None:
    for key, old in previous.items():
        if old is None:
            os.environ.pop(key, None)
        else:
            os.environ[key] = old


def run_inspect_view(
    *,
    log_dir: str,
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    credentials: Mapping[str, str] | None = None,
    view_fn: Callable[..., Any] | None = None,
) -> int:
    """Start Inspect View in-process against ``log_dir``; return exit code.

    Temporary AWS credentials (when provided) are applied only for the
    duration of the viewer and restored afterwards.
    """
    if view_fn is None:
        from inspect_ai import view as view_fn

    env_updates: dict[str, str] = {}
    if credentials:
        env_updates.update(credentials)
        if "AWS_DEFAULT_REGION" not in env_updates and "AWS_REGION" not in env_updates:
            env_updates["AWS_DEFAULT_REGION"] = DEFAULT_REGION

    previous = _apply_env(env_updates) if env_updates else {}
    try:
        view_fn(
            log_dir=log_dir,
            recursive=True,
            host=host,
            port=port,
        )
        return 0
    except FileNotFoundError as error:
        print(
            f"ERROR: Inspect could not open {log_dir}: {error}\n"
            "Hint: confirm the prefix with "
            "`uv run python scripts/view_inspect_logs_s3.py --list`.",
            file=sys.stderr,
        )
        return 2
    except KeyboardInterrupt:
        print("\nInspect View stopped.", file=sys.stderr)
        return 130
    finally:
        _restore_env(previous)


def describe_view_command(*, log_dir: str, port: int = DEFAULT_PORT) -> str:
    """Human-readable equivalent of the in-process viewer invocation."""
    return (
        f"inspect_ai.view(log_dir={log_dir!r}, recursive=True, "
        f"host={DEFAULT_HOST!r}, port={port})"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--log-dir",
        default=os.environ.get("TARS_EVAL_S3_URI")
        or default_log_dir(
            bucket=os.environ.get("TARS_EVAL_S3_BUCKET", DEFAULT_BUCKET),
            prefix_root=os.environ.get(
                "TARS_EVAL_S3_PREFIX_ROOT", DEFAULT_PREFIX_ROOT
            ),
        ),
        help=(
            "S3 URI for Inspect logs "
            f"(default: {default_log_dir()} or TARS_EVAL_S3_URI)"
        ),
    )
    parser.add_argument(
        "--role-arn",
        default=os.environ.get("TARS_EVAL_S3_ROLE_ARN", ""),
        help=(
            "IAM role ARN for qli aws export "
            "(default: TARS_EVAL_S3_ROLE_ARN, or QLI interactive selection)"
        ),
    )
    parser.add_argument(
        "--port",
        type=int,
        default=int(os.environ.get("TARS_EVAL_INSPECT_VIEW_PORT", DEFAULT_PORT)),
        help=f"Inspect View TCP port (default: {DEFAULT_PORT})",
    )
    parser.add_argument(
        "--use-ambient-credentials",
        action="store_true",
        help=(
            "Skip QLI and use AWS credentials already present in the environment "
            "/ default credential chain (e.g. after `weep export` or "
            "`qli aws export` in the parent shell)"
        ),
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List child prefixes under --log-dir and exit (does not start the viewer)",
    )
    parser.add_argument(
        "--print-command",
        action="store_true",
        help="Print the Inspect View invocation and exit without starting the server",
    )
    args = parser.parse_args(argv)

    try:
        log_dir = validate_s3_uri(args.log_dir)
        port = validate_port(args.port)
        role_arn = validate_role_arn(args.role_arn)
    except ViewConfigError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    if args.print_command:
        print(describe_view_command(log_dir=log_dir, port=port))
        print(f"# Open http://{DEFAULT_HOST}:{port} after the server starts")
        return 0

    credentials: dict[str, str] | None = None
    if not args.use_ambient_credentials:
        try:
            credentials = fetch_qli_credentials(role_arn=role_arn)
        except ViewConfigError as error:
            print(f"ERROR: {error}", file=sys.stderr)
            return 2
        print(
            "Authenticated via QLI/ConsoleMe "
            "(https://consoleme.sre.quintoandar.com.br/)."
        )
    else:
        print("Using ambient AWS credentials.")

    if args.list:
        try:
            children = list_child_prefixes(log_dir=log_dir, credentials=credentials)
        except Exception as error:  # noqa: BLE001
            print(f"ERROR: failed to list {log_dir}: {error}", file=sys.stderr)
            return 2
        if not children:
            print(f"No child prefixes under {log_dir}")
            return 0
        print(f"Child prefixes under {log_dir}:")
        for uri in children:
            print(f"  {uri}")
        return 0

    try:
        ensure_log_dir_readable(log_dir=log_dir, credentials=credentials)
    except ViewConfigError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    print("Starting Inspect View…")
    print(f"Inspect View log-dir: {log_dir}")
    print(f"Open http://{DEFAULT_HOST}:{port} (CTRL+C to quit)")

    return run_inspect_view(
        log_dir=log_dir,
        port=port,
        credentials=credentials,
    )


if __name__ == "__main__":
    raise SystemExit(main())
