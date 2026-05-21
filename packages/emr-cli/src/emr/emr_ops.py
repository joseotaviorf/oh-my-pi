from __future__ import annotations

import sys
import time
from typing import Any

import boto3
from botocore.exceptions import ClientError

from emr.config import normalize_tags
from emr.log_follow import (
    StepLogTailer,
    flush_step_logs_after_terminal,
    parse_s3_uri,
    step_logs_prefix,
)
from emr.steps import build_spark_step


def _emr_client(region: str | None):
    kwargs: dict[str, Any] = {}
    if region:
        kwargs["region_name"] = region
    return boto3.client("emr", **kwargs)


def _resolve_region(cfg: dict[str, Any]) -> str | None:
    return cfg.get("region") or cfg.get("aws_region")


def emr_console_cluster_url(*, region: str, cluster_id: str) -> str:
    """AWS console URL for the EMR cluster details page."""
    r = region.strip()
    return (
        f"https://{r}.console.aws.amazon.com/emr/home"
        f"?region={r}#/clusterDetails/{cluster_id}"
    )


def _console_region_from_client(client: Any, cfg: dict[str, Any]) -> str | None:
    meta_region = getattr(client.meta, "region_name", None)
    if meta_region:
        return str(meta_region).strip()
    resolved = _resolve_region(cfg)
    return str(resolved).strip() if resolved else None


def _print_cluster_console_url(
    client: Any, cfg: dict[str, Any], cluster_id: str
) -> None:
    region = _console_region_from_client(client, cfg)
    if region:
        print(
            "Cluster console URL: ",
            emr_console_cluster_url(region=region, cluster_id=cluster_id),
        )


def resolve_step_id_after_run(
    client, cluster_id: str, step_name: str, timeout_sec: int = 600
) -> str:
    """After run_job_flow, step ids appear once the cluster record exists."""
    deadline = time.time() + timeout_sec
    last_err: Exception | None = None
    while time.time() < deadline:
        try:
            resp = client.list_steps(ClusterId=cluster_id)
            steps = resp.get("Steps", [])
            for s in steps:
                if s.get("Name") == step_name:
                    return s["Id"]
            if steps:
                return steps[0]["Id"]
        except ClientError as e:
            last_err = e
            code = e.response.get("Error", {}).get("Code", "")
            if code not in ("InvalidRequestException", "ValidationException"):
                raise
        time.sleep(5)
    if last_err:
        print(f"Timed out resolving step id: {last_err}", file=sys.stderr)
    raise TimeoutError(f"No step id for cluster {cluster_id} within {timeout_sec}s")


def wait_for_step_terminal(
    client,
    cluster_id: str,
    step_id: str,
    poll_sec: float = 15.0,
    *,
    follow_logs: bool = False,
    log_uri: str | None = None,
    s3_client: Any | None = None,
) -> str:
    """Return terminal state: COMPLETED, FAILED, CANCELLED, INTERRUPTED."""
    terminal = {"COMPLETED", "FAILED", "CANCELLED", "INTERRUPTED"}
    tailer: StepLogTailer | None = None
    log_bucket: str | None = None
    log_prefix: str | None = None
    if follow_logs and log_uri and s3_client:
        tailer = StepLogTailer()
        log_bucket, log_prefix = step_logs_prefix(log_uri, cluster_id, step_id)
        print(f"Polling logs from S3: {log_bucket}/{log_prefix}", flush=True)

    while True:
        if tailer and log_bucket and log_prefix and s3_client:
            tailer.poll_with_stall_warning(s3_client, log_bucket, log_prefix)
        resp = client.describe_step(ClusterId=cluster_id, StepId=step_id)
        state = resp["Step"]["Status"]["State"]
        if state in terminal:
            if tailer and log_bucket and log_prefix and s3_client:
                tailer.poll_with_stall_warning(s3_client, log_bucket, log_prefix)
                flush_step_logs_after_terminal(
                    s3_client, tailer, log_bucket, log_prefix
                )
                if not tailer.saw_any_key and log_uri:
                    _, log_base = parse_s3_uri(log_uri)
                    leaf = log_base.rstrip("/").rsplit("/", 1)[-1]
                    dump_rel = f"{leaf}/{cluster_id}/steps/{step_id}/"
                    print(
                        "No step logs appeared under the prefix above. After the run, "
                        f"try: emr-cli dump-logs {dump_rel}",
                        file=sys.stderr,
                        flush=True,
                    )
            return state
        time.sleep(poll_sec)


def _poll_sec(cfg: dict[str, Any]) -> float:
    return float(cfg["poll_sec"])


def build_instances_block(
    cfg: dict[str, Any], *, keep_job_flow_alive_when_no_steps: bool
) -> dict[str, Any]:
    core_count = int(cfg["core_instance_count"])
    use_spot = bool(cfg.get("use_spot", True))
    core_market = "SPOT" if use_spot else "ON_DEMAND"
    return {
        "InstanceGroups": [
            {
                "Name": "Master nodes",
                "Market": "ON_DEMAND",
                "InstanceRole": "MASTER",
                "InstanceType": cfg["master_instance_type"],
                "InstanceCount": 1,
            },
            {
                "Name": "Core nodes",
                "Market": core_market,
                "InstanceRole": "CORE",
                "InstanceType": cfg["core_instance_type"],
                "InstanceCount": max(1, core_count),
            },
        ],
        "Ec2SubnetId": cfg["subnet_id"],
        "KeepJobFlowAliveWhenNoSteps": keep_job_flow_alive_when_no_steps,
    }


def _build_run_job_flow_payload(
    cfg: dict[str, Any],
    *,
    steps: list[dict[str, Any]],
    keep_job_flow_alive_when_no_steps: bool,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "Name": cfg["name"],
        "ReleaseLabel": cfg["release_label"],
        "Applications": cfg["applications"],
        "JobFlowRole": cfg["job_flow_role"],
        "ServiceRole": cfg["service_role"],
        "Instances": build_instances_block(
            cfg, keep_job_flow_alive_when_no_steps=keep_job_flow_alive_when_no_steps
        ),
        "Steps": steps,
        "VisibleToAllUsers": bool(cfg["visible_to_all_users"]),
    }
    if cfg.get("log_uri"):
        payload["LogUri"] = cfg["log_uri"]

    emr_cfgs = cfg.get("configurations") or []
    if emr_cfgs:
        payload["Configurations"] = emr_cfgs

    bootstrap_uri = cfg.get("bootstrap_script_uri")
    if bootstrap_uri:
        script_action: dict[str, Any] = {"Path": str(bootstrap_uri)}
        bs_args = cfg.get("bootstrap_script_args")
        if bs_args:
            script_action["Args"] = [str(a) for a in bs_args]
        payload["BootstrapActions"] = [
            {
                "Name": "Worker init script",
                "ScriptBootstrapAction": script_action,
            }
        ]

    # Idle TTL from settings applies only to persistent clusters (not transient RunJobFlow).
    if keep_job_flow_alive_when_no_steps:
        idle = cfg.get("idle_timeout_sec")
        if idle is not None:
            payload["AutoTerminationPolicy"] = {"IdleTimeout": int(idle)}

    tags = normalize_tags(cfg.get("tags"))
    if tags:
        payload["Tags"] = tags

    return payload


def submit_transient(
    cfg: dict[str, Any], *, wait: bool, follow_logs: bool = False
) -> None:
    client = _emr_client(_resolve_region(cfg))
    step = build_spark_step(
        name=cfg["step_name"],
        action_on_failure=cfg["action_on_failure"],
        s3_py_uri=cfg["s3_uri"],
        deploy_mode=cfg["deploy_mode"],
        py_script_args=cfg.get("job_script_args"),
    )

    payload = _build_run_job_flow_payload(
        cfg,
        steps=[step],
        keep_job_flow_alive_when_no_steps=False,
    )

    resp = client.run_job_flow(**payload)
    job_flow_id = resp["JobFlowId"]
    print(f"JobFlowId={job_flow_id}")
    _print_cluster_console_url(client, cfg, job_flow_id)

    if not wait:
        return

    step_id = resolve_step_id_after_run(client, job_flow_id, cfg["step_name"])
    print(f"StepId={step_id}")
    s3_client: Any | None = None
    if follow_logs:
        s3_client = boto3.client("s3", region_name=_resolve_region(cfg))
    state = wait_for_step_terminal(
        client,
        job_flow_id,
        step_id,
        poll_sec=_poll_sec(cfg),
        follow_logs=follow_logs,
        log_uri=str(cfg["log_uri"]) if cfg.get("log_uri") else None,
        s3_client=s3_client,
    )
    print(f"Step finished: {state}")
    if state != "COMPLETED":
        raise SystemExit(1)


def create_persistent_cluster(cfg: dict[str, Any]) -> None:
    """RunJobFlow with no steps; cluster stays up until idle TTL (if set) or terminate."""
    client = _emr_client(_resolve_region(cfg))
    payload = _build_run_job_flow_payload(
        cfg,
        steps=[],
        keep_job_flow_alive_when_no_steps=True,
    )
    resp = client.run_job_flow(**payload)
    job_flow_id = resp["JobFlowId"]
    print(f"JobFlowId={job_flow_id}")
    _print_cluster_console_url(client, cfg, job_flow_id)


def terminate_cluster(*, cluster_id: str, region: str | None) -> None:
    client = _emr_client(region)
    client.terminate_job_flows(JobFlowIds=[cluster_id])
    print(f"TerminateJobFlow requested for {cluster_id}")


def submit_step_to_cluster(
    cfg: dict[str, Any], *, cluster_id: str, wait: bool, follow_logs: bool = False
) -> None:
    client = _emr_client(_resolve_region(cfg))
    step = build_spark_step(
        name=cfg["step_name"],
        action_on_failure=cfg["action_on_failure"],
        s3_py_uri=cfg["s3_uri"],
        deploy_mode=cfg["deploy_mode"],
        py_script_args=cfg.get("job_script_args"),
    )
    resp = client.add_job_flow_steps(JobFlowId=cluster_id, Steps=[step])
    step_ids = resp.get("StepIds") or []
    step_id = (
        step_ids[0]
        if step_ids
        else resolve_step_id_after_run(client, cluster_id, cfg["step_name"])
    )
    print(f"StepId={step_id}")

    if not wait:
        return

    s3_client: Any | None = None
    if follow_logs:
        s3_client = boto3.client("s3", region_name=_resolve_region(cfg))
    state = wait_for_step_terminal(
        client,
        cluster_id,
        step_id,
        poll_sec=_poll_sec(cfg),
        follow_logs=follow_logs,
        log_uri=str(cfg["log_uri"]) if cfg.get("log_uri") else None,
        s3_client=s3_client,
    )
    print(f"Step finished: {state}")
    if state != "COMPLETED":
        raise SystemExit(1)
