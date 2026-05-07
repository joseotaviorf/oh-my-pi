"""Unit tests for ``emr.emr_ops`` helpers (no AWS calls)."""

from __future__ import annotations

from emr.emr_ops import _build_run_job_flow_payload, build_instances_block


def _minimal_run_job_cfg(**extra: object) -> dict:
    cfg = {
        "name": "flow",
        "release_label": "emr-7.5.0",
        "subnet_id": "subnet-abc",
        "job_flow_role": "emr-role",
        "service_role": "arn:aws:iam::1:role/EMR_DefaultRole_V2",
        "master_instance_type": "m5.xlarge",
        "core_instance_type": "m5.xlarge",
        "core_instance_count": 2,
        "visible_to_all_users": True,
        "applications": [{"Name": "Spark"}],
        "configurations": [],
        "tags": [{"Key": "for-use-with-amazon-emr-managed-policies", "Value": "true"}],
    }
    cfg.update(extra)
    return cfg


def test_build_run_job_flow_payload_bootstrap_args() -> None:
    cfg = _minimal_run_job_cfg(
        bootstrap_script_uri="s3://b/init.sh",
        bootstrap_script_args=["s3://artifacts.example"],
        idle_timeout_sec=600,
    )
    payload = _build_run_job_flow_payload(
        cfg, steps=[], keep_job_flow_alive_when_no_steps=True
    )
    sba = payload["BootstrapActions"][0]["ScriptBootstrapAction"]
    assert sba["Path"] == "s3://b/init.sh"
    assert sba["Args"] == ["s3://artifacts.example"]


def test_build_run_job_flow_payload_includes_configurations_when_set() -> None:
    cfgs = [
        {
            "Classification": "delta-defaults",
            "Properties": {"delta.enabled": "true"},
        }
    ]
    cfg = _minimal_run_job_cfg(
        configurations=cfgs,
        idle_timeout_sec=600,
    )
    payload = _build_run_job_flow_payload(
        cfg, steps=[], keep_job_flow_alive_when_no_steps=True
    )
    assert payload["Configurations"] == cfgs


def test_build_run_job_flow_payload_bootstrap_without_args() -> None:
    cfg = _minimal_run_job_cfg(bootstrap_script_uri="s3://b/init.sh")
    payload = _build_run_job_flow_payload(
        cfg, steps=[], keep_job_flow_alive_when_no_steps=False
    )
    sba = payload["BootstrapActions"][0]["ScriptBootstrapAction"]
    assert sba["Path"] == "s3://b/init.sh"
    assert "Args" not in sba


def test_build_instances_block_core_spot_when_use_spot_true() -> None:
    cfg = {
        "master_instance_type": "m5.xlarge",
        "core_instance_type": "m5.xlarge",
        "core_instance_count": 2,
        "subnet_id": "subnet-abc",
        "use_spot": True,
    }
    out = build_instances_block(cfg, keep_job_flow_alive_when_no_steps=False)
    groups = out["InstanceGroups"]
    assert groups[0]["Market"] == "ON_DEMAND"
    assert groups[0]["InstanceRole"] == "MASTER"
    assert groups[1]["Market"] == "SPOT"
    assert groups[1]["InstanceRole"] == "CORE"


def test_build_instances_block_core_on_demand_when_use_spot_false() -> None:
    cfg = {
        "master_instance_type": "m5.xlarge",
        "core_instance_type": "m5.xlarge",
        "core_instance_count": 1,
        "subnet_id": "subnet-abc",
        "use_spot": False,
    }
    out = build_instances_block(cfg, keep_job_flow_alive_when_no_steps=True)
    assert out["InstanceGroups"][1]["Market"] == "ON_DEMAND"


def test_build_instances_block_defaults_core_to_spot_without_key() -> None:
    cfg = {
        "master_instance_type": "m5.xlarge",
        "core_instance_type": "m5.xlarge",
        "core_instance_count": 1,
        "subnet_id": "subnet-abc",
    }
    out = build_instances_block(cfg, keep_job_flow_alive_when_no_steps=False)
    assert out["InstanceGroups"][1]["Market"] == "SPOT"
