"""AWS credential checks and automatic refresh via weep (migration-emr-cli)."""

from __future__ import annotations

import logging
import os
import subprocess
from collections.abc import Callable
from typing import TypeVar

import boto3
from botocore.exceptions import BotoCoreError, ClientError

from emr.paths import package_root

logger = logging.getLogger(__name__)

EXPIRED_TOKEN_CODES = frozenset(
    {
        "ExpiredToken",
        "ExpiredTokenException",
        "InvalidClientTokenId",
        "RequestExpired",
        "UnrecognizedClientException",
    }
)

T = TypeVar("T")


def is_expired_token_error(exc: BaseException) -> bool:
    if isinstance(exc, ClientError):
        code = exc.response.get("Error", {}).get("Code", "")
        return code in EXPIRED_TOKEN_CODES
    message = str(exc).lower()
    return "expiredtoken" in message or "expired token" in message


def aws_credentials_valid(region: str = "us-east-1") -> bool:
    try:
        boto3.client("sts", region_name=region).get_caller_identity()
        return True
    except ClientError as exc:
        if is_expired_token_error(exc):
            return False
        raise
    except BotoCoreError:
        return False


def refresh_aws_credentials_via_weep(emr_env: str = "prod") -> None:
    """Run ``make weep-auth`` to write fresh credentials to ``~/.aws/credentials``."""
    emr_cli_root = package_root()
    weep_bin = emr_cli_root / "dist" / "weep"
    if not weep_bin.exists():
        logger.info("weep not installed — running make weep-install")
        install = subprocess.run(
            ["make", "weep-install"],
            cwd=str(emr_cli_root),
            capture_output=True,
            text=True,
        )
        if install.returncode != 0:
            raise RuntimeError(
                f"make weep-install failed:\n{install.stdout}\n{install.stderr}".strip()
            )

    logger.info("Refreshing AWS credentials via weep (EMR_ENVIRONMENT=%s)", emr_env)
    env = os.environ.copy()
    env["EMR_ENVIRONMENT"] = emr_env
    result = subprocess.run(
        ["make", "weep-auth"],
        cwd=str(emr_cli_root),
        env=env,
        capture_output=True,
        text=True,
    )
    output = (result.stdout + "\n" + result.stderr).strip()
    if result.returncode != 0:
        raise RuntimeError(f"make weep-auth failed:\n{output}")

    if output:
        for line in output.splitlines():
            if line.strip():
                logger.info("weep: %s", line.strip())

    if not aws_credentials_valid():
        raise RuntimeError(
            "weep-auth finished but AWS credentials are still invalid. "
            "Complete ConsoleMe/SSO in the browser if prompted, then retry."
        )


def ensure_aws_credentials(
    emr_env: str = "prod",
    *,
    region: str = "us-east-1",
    force_refresh: bool = False,
) -> None:
    """Validate STS; refresh with weep when missing or expired."""
    if force_refresh or not aws_credentials_valid(region):
        if not force_refresh:
            logger.warning("AWS credentials missing or expired — running weep-auth")
        refresh_aws_credentials_via_weep(emr_env)
        return

    identity = boto3.client("sts", region_name=region).get_caller_identity()
    logger.debug(
        "AWS credentials ok (account=%s, arn=%s)",
        identity.get("Account"),
        identity.get("Arn"),
    )


def call_with_aws_retry(
    operation: Callable[[], T],
    *,
    emr_env: str = "prod",
    region: str = "us-east-1",
    description: str = "AWS operation",
) -> T:
    """Run a boto3/AWS call; on ExpiredToken refresh via weep and retry once."""
    try:
        return operation()
    except (ClientError, BotoCoreError) as exc:
        if not is_expired_token_error(exc):
            raise
        logger.warning(
            "%s failed with expired token — refreshing via weep", description
        )
        ensure_aws_credentials(emr_env, region=region, force_refresh=True)
        return operation()
