"""Dual-role boto3 sessions via Weep credential_process (no ~/.aws/config)."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from datetime import datetime, timedelta, timezone
from functools import lru_cache
from typing import Any, Literal, NamedTuple

import boto3

Environment = Literal["forno", "prod"]

ENVIRONMENTS: dict[Environment, dict[str, str]] = {
    "forno": {
        "emr": "arn:aws:iam::713278628093:role/sso_DataAndAnalyticsEMRUser_staff",
        "ec2": "arn:aws:iam::713278628093:role/sso_DataAndAnalyticsManagement_Staff",
        "logs_base_uri": "s3://artifacts.s3.forno.data.quintoandar.com.br/emr/logs/dags/",
    },
    "prod": {
        "emr": "arn:aws:iam::206390561754:role/sso_DataAndAnalyticsEMRUser_staff",
        "ec2": "arn:aws:iam::206390561754:role/sso_DataAndAnalyticsManagement_Staff",
        "logs_base_uri": "s3://artifacts.s3.data.quintoandar.com.br/emr/logs/dags/",
    },
}

DEFAULT_ENVIRONMENT: Environment = "forno"
DEFAULT_REGION = "us-east-1"
CREDENTIAL_REFRESH_BUFFER = timedelta(minutes=5)


class CachedCredentials(NamedTuple):
    access_key_id: str
    secret_access_key: str
    session_token: str | None
    expiration: datetime | None


_credential_cache: dict[str, CachedCredentials] = {}


def available_environments() -> list[Environment]:
    return list(ENVIRONMENTS.keys())


def normalize_environment(environment: str | None = None) -> Environment:
    raw = environment or os.environ.get("EMR_MONITOR_ENVIRONMENT", DEFAULT_ENVIRONMENT)
    key = raw.strip().lower()
    if key not in ENVIRONMENTS:
        raise ValueError(f"Unknown environment {raw!r}; expected forno or prod")
    return key  # type: ignore[return-value]


def emr_role_arn(environment: str | None = None) -> str:
    override = os.environ.get("EMR_MONITOR_EMR_ROLE_ARN")
    if override:
        return override
    return ENVIRONMENTS[normalize_environment(environment)]["emr"]


def ec2_role_arn(environment: str | None = None) -> str:
    override = os.environ.get("EMR_MONITOR_EC2_ROLE_ARN")
    if override:
        return override
    return ENVIRONMENTS[normalize_environment(environment)]["ec2"]


def logs_base_uri(environment: str | None = None) -> str:
    override = os.environ.get("EMR_MONITOR_LOGS_BASE_URI")
    if override:
        return override
    return ENVIRONMENTS[normalize_environment(environment)]["logs_base_uri"]


def default_region() -> str:
    return os.environ.get("EMR_MONITOR_REGION", DEFAULT_REGION)


def clear_credential_cache() -> None:
    _credential_cache.clear()


@lru_cache(maxsize=1)
def _weep_bin() -> str:
    candidates = [
        os.environ.get("WEEP_BIN", ""),
        shutil.which("weep") or "",
        os.path.expanduser("~/git/bi-etl-ejuice/packages/emr-cli/dist/weep"),
    ]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
    raise RuntimeError(
        "weep not found. Install via bi-etl-ejuice packages/emr-cli (make weep-install) "
        "or set WEEP_BIN to the weep binary path."
    )


def _parse_expiration(raw: str | None) -> datetime | None:
    if not raw:
        return None
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))


def _credentials_fresh(creds: CachedCredentials) -> bool:
    if creds.expiration is None:
        return True
    return creds.expiration > datetime.now(timezone.utc) + CREDENTIAL_REFRESH_BUFFER


def _fetch_credentials(role_arn: str) -> CachedCredentials:
    cached = _credential_cache.get(role_arn)
    if cached and _credentials_fresh(cached):
        return cached

    proc = subprocess.run(
        [_weep_bin(), "credential_process", role_arn],
        capture_output=True,
        text=True,
        check=False,
        timeout=60,
    )
    if proc.returncode != 0:
        stderr = (proc.stderr or proc.stdout or "").strip()
        raise RuntimeError(
            f"Weep credential_process failed for {role_arn}: {stderr or 'unknown error'}"
        )

    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"Weep returned invalid JSON for {role_arn}: {proc.stdout[:200]}"
        ) from exc

    creds = CachedCredentials(
        access_key_id=payload["AccessKeyId"],
        secret_access_key=payload["SecretAccessKey"],
        session_token=payload.get("SessionToken"),
        expiration=_parse_expiration(payload.get("Expiration")),
    )
    _credential_cache[role_arn] = creds
    return creds


def _session_for_role(role_arn: str, region: str) -> boto3.Session:
    creds = _fetch_credentials(role_arn)
    return boto3.Session(
        aws_access_key_id=creds.access_key_id,
        aws_secret_access_key=creds.secret_access_key,
        aws_session_token=creds.session_token,
        region_name=region,
    )


def _client(
    service_name: str,
    *,
    region: str,
    environment: str | None,
    role: Literal["emr", "ec2"],
) -> Any:
    role_arn = emr_role_arn(environment) if role == "emr" else ec2_role_arn(environment)
    return _session_for_role(role_arn, region).client(service_name)


def client_emr(region: str | None = None, environment: str | None = None) -> Any:
    return _client("emr", region=region or default_region(), environment=environment, role="emr")


def client_cloudwatch_emr(
    region: str | None = None, environment: str | None = None
) -> Any:
    return _client(
        "cloudwatch", region=region or default_region(), environment=environment, role="emr"
    )


def client_cloudwatch_ec2(
    region: str | None = None, environment: str | None = None
) -> Any:
    return _client(
        "cloudwatch", region=region or default_region(), environment=environment, role="ec2"
    )


def client_ec2(region: str | None = None, environment: str | None = None) -> Any:
    return _client("ec2", region=region or default_region(), environment=environment, role="ec2")


def client_s3(region: str | None = None, environment: str | None = None) -> Any:
    return _client("s3", region=region or default_region(), environment=environment, role="ec2")


def role_identity(
    role_arn: str, region: str | None = None
) -> str:
    """Return STS caller ARN for display; empty string on failure."""
    try:
        sts = _session_for_role(role_arn, region or default_region()).client("sts")
        return sts.get_caller_identity().get("Arn", "")
    except Exception:
        return ""


def validate_roles(
    region: str | None = None, environment: str | None = None
) -> dict[str, str]:
    """Return role label -> active caller ARN for sidebar diagnostics."""
    resolved_region = region or default_region()
    out: dict[str, str] = {}
    for label, role_arn in (
        ("EMR", emr_role_arn(environment)),
        ("EC2", ec2_role_arn(environment)),
    ):
        arn = role_identity(role_arn, resolved_region)
        short_role = role_arn.rsplit("/", 1)[-1]
        out[label] = arn or f"(unable to authenticate as {short_role})"
    return out
