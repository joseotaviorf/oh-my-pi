"""Unit tests for ``emr.emr_ops`` helpers (no AWS calls)."""

from __future__ import annotations

from emr.emr_ops import build_instances_block


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
