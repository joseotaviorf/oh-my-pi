from __future__ import annotations

import sys
import time
from typing import Any

import boto3
from botocore.exceptions import ClientError

from emr.config import normalize_tags
from emr.steps import build_spark_step


def _emr_client(region: str | None):
    kwargs: dict[str, Any] = {}
    if region:
        kwargs["region_name"] = region
    return boto3.client("emr", **kwargs)


def _resolve_region(cfg: dict[str, Any]) -> str | None:
    return cfg.get("region") or cfg.get("aws_region")


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
) -> str:
    """Return terminal state: COMPLETED, FAILED, CANCELLED, INTERRUPTED."""
    terminal = {"COMPLETED", "FAILED", "CANCELLED", "INTERRUPTED"}
    while True:
        resp = client.describe_step(ClusterId=cluster_id, StepId=step_id)
        state = resp["Step"]["Status"]["State"]
        if state in terminal:
            return state
        time.sleep(poll_sec)


def _poll_sec(cfg: dict[str, Any]) -> float:
    return float(cfg["poll_sec"])


def build_instances_block(
    cfg: dict[str, Any], *, keep_job_flow_alive_when_no_steps: bool
) -> dict[str, Any]:
    core_count = int(cfg["core_instance_count"])
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
                "Market": "ON_DEMAND",
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
        "Applications": [{"Name": "Spark"}],
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

    bootstrap_uri = cfg.get("bootstrap_script_uri")
    if bootstrap_uri:
        payload["BootstrapActions"] = [
            {
                "Name": "Worker init script",
                "ScriptBootstrapAction": {"Path": str(bootstrap_uri)},
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


def submit_transient(cfg: dict[str, Any], *, wait: bool) -> None:
    client = _emr_client(_resolve_region(cfg))
    step = build_spark_step(
        name=cfg["step_name"],
        action_on_failure=cfg["action_on_failure"],
        s3_py_uri=cfg["s3_uri"],
        deploy_mode=cfg["deploy_mode"],
    )

    payload = _build_run_job_flow_payload(
        cfg,
        steps=[step],
        keep_job_flow_alive_when_no_steps=False,
    )

    resp = client.run_job_flow(**payload)
    job_flow_id = resp["JobFlowId"]
    print(f"JobFlowId={job_flow_id}")

    if not wait:
        return

    step_id = resolve_step_id_after_run(client, job_flow_id, cfg["step_name"])
    print(f"StepId={step_id}")
    state = wait_for_step_terminal(
        client, job_flow_id, step_id, poll_sec=_poll_sec(cfg)
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
    print(f"JobFlowId={resp['JobFlowId']}")


def terminate_cluster(*, cluster_id: str, region: str | None) -> None:
    client = _emr_client(region)
    client.terminate_job_flows(JobFlowIds=[cluster_id])
    print(f"TerminateJobFlow requested for {cluster_id}")


def submit_step_to_cluster(cfg: dict[str, Any], *, cluster_id: str, wait: bool) -> None:
    client = _emr_client(_resolve_region(cfg))
    step = build_spark_step(
        name=cfg["step_name"],
        action_on_failure=cfg["action_on_failure"],
        s3_py_uri=cfg["s3_uri"],
        deploy_mode=cfg["deploy_mode"],
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

    state = wait_for_step_terminal(client, cluster_id, step_id, poll_sec=_poll_sec(cfg))
    print(f"Step finished: {state}")
    if state != "COMPLETED":
        raise SystemExit(1)
