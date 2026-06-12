"""Thin bridge to skill-local migration-emr-cli for migration validation."""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import uuid
from pathlib import Path
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple, TypeVar

VALIDATE_JOB_REL = "samples/job/migration_validate_job.py"

import yaml

from paths import MIGRATION_EMR_CLI_ROOT

MIGRATION_VALIDATE_SETTINGS = (
    MIGRATION_EMR_CLI_ROOT / "config" / "migration-validate.yml"
)
VALIDATE_JOB = (
    MIGRATION_EMR_CLI_ROOT / "samples" / "job" / "migration_validate_job.py"
)

T = TypeVar("T")


def _ensure_emr_import_path() -> None:
    src = MIGRATION_EMR_CLI_ROOT / "src"
    if str(src) not in sys.path:
        sys.path.insert(0, str(src))


def ensure_aws_credentials(
    emr_env: str = "prod",
    *,
    region: str = "us-east-1",
    force_refresh: bool = False,
) -> None:
    _ensure_emr_import_path()
    from emr.aws_auth import ensure_aws_credentials as _ensure

    _ensure(emr_env, region=region, force_refresh=force_refresh)


def call_with_aws_retry(
    operation: Callable[[], T],
    *,
    emr_env: str = "prod",
    region: str = "us-east-1",
    description: str = "AWS operation",
) -> T:
    _ensure_emr_import_path()
    from emr.aws_auth import call_with_aws_retry as _retry

    return _retry(operation, emr_env=emr_env, region=region, description=description)


def parse_result_json(text: str) -> Optional[Dict[str, Any]]:
    _ensure_emr_import_path()
    from emr.result_fetch import parse_result_json_line

    return parse_result_json_line(text)


def resolve_result_from_output(
    output: str,
    *,
    returncode: int,
    result_s3_uri: Optional[str] = None,
    emr_env: str = "prod",
) -> Tuple[Optional[Dict[str, Any]], Optional[str]]:
    """Parse RESULT_JSON= from migration-emr-cli stdout; fall back to S3 poll."""
    payload = parse_result_json(output)
    if payload is not None:
        return payload, payload.get("error")

    if result_s3_uri:
        _ensure_emr_import_path()
        from emr.result_fetch import fetch_json_from_s3

        try:
            payload = call_with_aws_retry(
                lambda: fetch_json_from_s3(result_s3_uri),
                emr_env=emr_env,
                description="S3 validation result fetch",
            )
        except Exception as exc:
            return None, f"S3 result fetch failed: {exc}"
        if payload is not None:
            return payload, payload.get("error")

    if returncode != 0:
        return None, output.strip() or f"migration-emr-cli exited with code {returncode}"

    if result_s3_uri:
        return None, f"Missing validation result at {result_s3_uri}"
    return None, "Missing RESULT_JSON= in migration-emr-cli output"


def migration_env(emr_env: str = "prod") -> Dict[str, str]:
    env = os.environ.copy()
    env["EMR_ENVIRONMENT"] = emr_env
    env["EMR_SETTINGS_FILE"] = str(MIGRATION_VALIDATE_SETTINGS)
    # Avoid uv stderr warnings polluting captured JSON stdout when falling back to uv run.
    env.pop("VIRTUAL_ENV", None)
    return env


def emr_cli_prefix() -> List[str]:
    dist = MIGRATION_EMR_CLI_ROOT / "dist" / "migration-emr-cli"
    if dist.exists():
        return [str(dist)]
    if (MIGRATION_EMR_CLI_ROOT / "pyproject.toml").exists():
        return ["uv", "run", "migration-emr-cli"]
    raise FileNotFoundError(
        f"migration-emr-cli not found under {MIGRATION_EMR_CLI_ROOT}. "
        "Run 'make sync && make build-executable' in migration-emr-cli/."
    )


def _parse_cli_json(output: str) -> Any:
    """Parse JSON from migration-emr-cli stdout, tolerating trailing stderr noise."""
    text = output.strip()
    if not text:
        raise ValueError("empty migration-emr-cli output")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        for start_char in ("{", "["):
            idx = text.find(start_char)
            if idx >= 0:
                payload, _ = json.JSONDecoder().raw_decode(text, idx)
                return payload
        raise


def run_emr_cli(
    args: Sequence[str],
    *,
    emr_env: str = "prod",
    quiet: bool = True,
) -> Tuple[int, str]:
    cmd = [*emr_cli_prefix(), *args]
    if quiet:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=migration_env(emr_env),
            cwd=str(MIGRATION_EMR_CLI_ROOT),
        )
        return result.returncode, (result.stdout or "") + (result.stderr or "")

    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=migration_env(emr_env),
        cwd=str(MIGRATION_EMR_CLI_ROOT),
    )
    captured: List[str] = []
    if process.stdout is not None:
        for line in process.stdout:
            sys.stdout.write(line)
            sys.stdout.flush()
            captured.append(line)
    return process.wait(), "".join(captured)


def load_staging_uri(emr_env: str = "prod") -> str:
    with MIGRATION_VALIDATE_SETTINGS.open(encoding="utf-8") as handle:
        cfg = yaml.safe_load(handle) or {}
    staging_uri = str(cfg.get("staging_uri", "")).rstrip("/") + "/"
    if not staging_uri.startswith("s3://"):
        raise ValueError(f"staging_uri missing in {MIGRATION_VALIDATE_SETTINGS}")
    return staging_uri


class SqlStager:
    """Stage SQL and derive result URIs via migration-emr-cli."""

    def __init__(
        self,
        run_id: Optional[str] = None,
        emr_env: str = "prod",
        staging_uri: Optional[str] = None,
    ):
        self.emr_env = emr_env
        self.run_id = run_id or uuid.uuid4().hex
        resolved = (staging_uri or load_staging_uri(emr_env)).rstrip("/") + "/"
        self.staging_uri = resolved

    def _staging_relpath(
        self,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
        suffix: str,
    ) -> str:
        return (
            f"migration-validate/{self.run_id}/"
            f"{domain}/{dag_name}/{layer}/{table_name}.{suffix}"
        )

    def _object_uri(
        self,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
        suffix: str,
    ) -> str:
        bucket, prefix = self.staging_uri.replace("s3://", "", 1).split("/", 1)
        key = f"{prefix}{self._staging_relpath(domain, dag_name, layer, table_name, suffix)}"
        return f"s3://{bucket}/{key}"

    def stage_sql(
        self,
        sql_text: str,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
    ) -> str:
        key = self._staging_relpath(domain, dag_name, layer, table_name, "sql")
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, encoding="utf-8") as handle:
            handle.write(sql_text)
            temp_path = Path(handle.name)
        try:
            returncode, output = run_emr_cli(
                ["stage", "--key", key, "--file", str(temp_path)],
                emr_env=self.emr_env,
            )
            if returncode != 0:
                raise RuntimeError(output.strip() or "migration-emr-cli stage failed")
            lines = [line.strip() for line in output.splitlines() if line.strip().startswith("s3://")]
            if not lines:
                raise RuntimeError(
                    f"migration-emr-cli stage did not return an s3:// URI:\n{output}"
                )
            return lines[-1]
        finally:
            temp_path.unlink(missing_ok=True)

    def result_uri_for(
        self,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
    ) -> str:
        """Legacy alias — prefer ``emr_result_uri_for`` (.emr.json)."""
        return self.emr_result_uri_for(domain, dag_name, layer, table_name)

    def emr_result_uri_for(
        self,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
    ) -> str:
        return self._object_uri(domain, dag_name, layer, table_name, "emr.json")

    def legacy_emr_result_uri_for(
        self,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
    ) -> str:
        return self._object_uri(domain, dag_name, layer, table_name, "json")

    def baseline_uri_for(
        self,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
    ) -> str:
        return self._object_uri(domain, dag_name, layer, table_name, "baseline.json")

    def report_uri_for(self, domain: str, dag_name: str) -> str:
        bucket, prefix = self.staging_uri.replace("s3://", "", 1).split("/", 1)
        key = f"{prefix}migration-validate/{self.run_id}/report/{domain}/{dag_name}.md"
        return f"s3://{bucket}/{key}"

    def manifest_uri(self) -> str:
        bucket, prefix = self.staging_uri.replace("s3://", "", 1).split("/", 1)
        key = f"{prefix}migration-validate/{self.run_id}/manifest.json"
        return f"s3://{bucket}/{key}"

    def log_uri_for(
        self,
        domain: str,
        dag_name: str,
        layer: str,
        table_name: str,
    ) -> str:
        return self._object_uri(domain, dag_name, layer, table_name, "log")


def split_s3_uri(uri: str) -> tuple[str, str]:
    _ensure_emr_import_path()
    from emr.result_fetch import split_s3_uri as _split

    return _split(uri)


def object_exists(s3_uri: str, *, emr_env: str = "prod") -> bool:
    bucket, key = split_s3_uri(s3_uri)
    _ensure_emr_import_path()
    import boto3
    from botocore.exceptions import ClientError

    client = boto3.client("s3")

    def _head() -> bool:
        try:
            client.head_object(Bucket=bucket, Key=key)
            return True
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"404", "NoSuchKey", "NotFound"}:
                return False
            raise

    return call_with_aws_retry(_head, emr_env=emr_env, description="S3 head_object")


def upload_json_to_s3(
    s3_uri: str,
    payload: Dict[str, Any],
    *,
    emr_env: str = "prod",
) -> None:
    bucket, key = split_s3_uri(s3_uri)
    body = json.dumps(payload, indent=2, default=str).encode("utf-8")
    _ensure_emr_import_path()
    import boto3

    client = boto3.client("s3")

    def _put() -> None:
        client.put_object(
            Bucket=bucket,
            Key=key,
            Body=body,
            ContentType="application/json",
        )

    call_with_aws_retry(_put, emr_env=emr_env, description="S3 put_object")


def delete_s3_object(s3_uri: str, *, emr_env: str = "prod") -> None:
    """Delete an S3 object if it exists (no-op when missing)."""
    if not s3_uri:
        return
    bucket, key = split_s3_uri(s3_uri)
    _ensure_emr_import_path()
    import boto3
    from botocore.exceptions import ClientError

    client = boto3.client("s3")

    def _delete() -> None:
        try:
            client.delete_object(Bucket=bucket, Key=key)
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code", "")
            if code in {"404", "NoSuchKey", "NotFound"}:
                return
            raise

    call_with_aws_retry(_delete, emr_env=emr_env, description="S3 delete_object")


def upload_text_to_s3(
    s3_uri: str,
    text: str,
    *,
    emr_env: str = "prod",
    content_type: str = "text/plain",
) -> None:
    bucket, key = split_s3_uri(s3_uri)
    _ensure_emr_import_path()
    import boto3

    client = boto3.client("s3")

    def _put() -> None:
        client.put_object(
            Bucket=bucket,
            Key=key,
            Body=text.encode("utf-8"),
            ContentType=content_type,
        )

    call_with_aws_retry(_put, emr_env=emr_env, description="S3 put_object text")


def download_json_from_s3(
    s3_uri: str,
    *,
    emr_env: str = "prod",
) -> Optional[Dict[str, Any]]:
    _ensure_emr_import_path()
    from emr.result_fetch import fetch_json_from_s3

    try:
        payload = call_with_aws_retry(
            lambda: fetch_json_from_s3(s3_uri, retries=1, delay_sec=0.0),
            emr_env=emr_env,
            description="S3 get_object json",
        )
    except Exception as exc:
        logger = __import__("logging").getLogger(__name__)
        logger.debug("download_json_from_s3 failed for %s: %s", s3_uri, exc)
        return None
    return payload


def describe_emr_step(
    cluster_id: str,
    step_id: str,
    *,
    emr_env: str = "prod",
) -> Optional[dict[str, Any]]:
    """Return EMR describe_step payload, or None when lookup fails."""
    if not cluster_id or not step_id:
        return None
    _ensure_emr_import_path()
    import boto3

    client = boto3.client("emr")

    def _describe() -> dict[str, Any]:
        return client.describe_step(ClusterId=cluster_id, StepId=step_id)

    try:
        return call_with_aws_retry(
            _describe,
            emr_env=emr_env,
            description="EMR describe_step",
        )
    except Exception:
        return None


def emr_step_state(
    cluster_id: str,
    step_id: str,
    *,
    emr_env: str = "prod",
) -> Optional[str]:
    resp = describe_emr_step(cluster_id, step_id, emr_env=emr_env)
    if not resp:
        return None
    return resp.get("Step", {}).get("Status", {}).get("State")


def emr_step_execution_start_ts(
    cluster_id: str,
    step_id: str,
    *,
    emr_env: str = "prod",
) -> Optional[float]:
    """Epoch seconds when the step left PENDING (CreationDateTime fallback)."""
    resp = describe_emr_step(cluster_id, step_id, emr_env=emr_env)
    if not resp:
        return None
    status = resp.get("Step", {}).get("Status", {})
    state = status.get("State")
    if state == "PENDING":
        return None
    timeline = status.get("Timeline") or {}
    for key in ("StartDateTime", "CreationDateTime"):
        ts = timeline.get(key)
        if ts is not None:
            return ts.timestamp()
    return None


def emr_step_failure_reason(
    cluster_id: str,
    step_id: str,
    *,
    emr_env: str = "prod",
) -> Optional[str]:
    """Return the EMR step failure reason/message if available."""
    resp = describe_emr_step(cluster_id, step_id, emr_env=emr_env)
    if not resp:
        return None
    status = resp.get("Step", {}).get("Status", {})
    failure_details = status.get("FailureDetails") or {}
    message = failure_details.get("Message")
    reason = failure_details.get("Reason")
    if message:
        return message
    if reason:
        return reason
    return None


def parse_step_id_from_output(output: str) -> Optional[str]:
    for line in output.splitlines():
        line = line.strip()
        if line.startswith("StepId="):
            return line.split("=", 1)[1].strip()
    return None


def describe_cluster_json(cluster_id: str, emr_env: str = "prod") -> Dict[str, Any]:
    returncode, output = run_emr_cli(
        ["describe-cluster", "--cluster-id", cluster_id, "--output", "json"],
        emr_env=emr_env,
    )
    if returncode != 0:
        raise RuntimeError(
            output.strip() or f"migration-emr-cli describe-cluster failed for {cluster_id}"
        )
    return _parse_cli_json(output)


def list_clusters_json(
    *,
    emr_env: str = "prod",
    tag_key: Optional[str] = None,
    tag_value: Optional[str] = None,
) -> List[Dict[str, Any]]:
    args = ["list-clusters", "--output", "json"]
    if tag_key and tag_value is not None:
        args.extend(["--tag", f"{tag_key}={tag_value}"])
    returncode, output = run_emr_cli(args, emr_env=emr_env)
    if returncode != 0:
        return []
    payload = _parse_cli_json(output)
    return payload if isinstance(payload, list) else []
