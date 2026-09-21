from __future__ import annotations

from emr_plugin.instance_alternates import (
    alternates,
    first_x86,
    is_graviton,
    with_alternates,
)
from emr_plugin.template_translator import translate


def _fleet_base(**overrides) -> dict:
    base = {
        "cluster_name": "test",
        "spark_version": "emr-7.12.0",
        "master_node_type_id": "r6g.xlarge",
        "core_nodes": {
            "instance_types": ["r6g.xlarge"],
            "target_on_demand": 1,
            "target_spot": 0,
        },
        "aws_attributes": {
            "availability": "ON_DEMAND",
            "instance_profile_arn": "arn:aws:iam::123:instance-profile/x",
            "ebs_volume_count": 1,
            "ebs_volume_size": 100,
            "ebs_volume_type": "gp3",
        },
        "emr_subnet_id": "subnet-1",
        "emr_service_role": "EMR_DefaultRole",
    }
    base.update(overrides)
    return base


def _instance_types(fleet: dict) -> list:
    return [config["InstanceType"] for config in fleet["InstanceTypeConfigs"]]


def test_alternates_mappings():
    assert alternates("r6g.xlarge") == [
        "r7g.xlarge",
        "r6a.xlarge",
        "r6i.xlarge",
        "r7i.xlarge",
        "r7a.xlarge",
    ]
    assert alternates("r6gd.4xlarge") == ["r7gd.4xlarge", "r6id.4xlarge"]
    # x86 families expand to other x86 alternates (cheapest first)
    assert alternates("r6a.2xlarge") == ["r6i.2xlarge", "r7i.2xlarge", "r7a.2xlarge"]
    assert alternates("c6a.xlarge") == ["c6i.xlarge", "c7i.xlarge", "c7a.xlarge"]
    assert alternates("m6i.4xlarge") == ["m6a.4xlarge", "m7i.4xlarge", "m7a.4xlarge"]
    assert alternates("m5.xlarge") == []
    assert alternates("invalid") == []
    assert alternates(None) == []


def test_first_x86():
    assert first_x86("r6g.xlarge") == "r6a.xlarge"
    assert first_x86("r6gd.2xlarge") == "r6id.2xlarge"
    assert first_x86("r6a.xlarge") is None
    assert first_x86("m5.xlarge") is None


def test_is_graviton():
    assert is_graviton("r6g.xlarge") is True
    assert is_graviton("r7gd.2xlarge") is True
    assert is_graviton("c8g.4xlarge") is True
    assert is_graviton("m6gd.8xlarge") is True
    assert is_graviton("r6a.xlarge") is False
    assert is_graviton("m6i.2xlarge") is False
    assert is_graviton("c7a.4xlarge") is False
    assert is_graviton("m5.xlarge") is False
    assert is_graviton("invalid") is False
    assert is_graviton(None) is False


def test_with_alternates_truncates_at_30():
    types = [
        "r6g.xlarge",
        "r6g.2xlarge",
        "r6g.4xlarge",
        "r6g.8xlarge",
        "r7g.xlarge",
        "r7g.2xlarge",
        "r7g.4xlarge",
        "r7g.8xlarge",
        "c6g.xlarge",
        "c6g.2xlarge",
    ]
    expanded = with_alternates(types)
    assert len(expanded) == 30


def test_master_fleet_arm_first_with_alternates_and_priorities():
    cfg = _fleet_base(master_node_type_id="r6g.xlarge")
    out = translate(cfg)

    master = out["Instances"]["InstanceFleets"][0]
    expected_types = [
        "r6g.xlarge",
        "r7g.xlarge",
        "r6a.xlarge",
        "r6i.xlarge",
        "r7i.xlarge",
        "r7a.xlarge",
    ]
    assert _instance_types(master) == expected_types
    for idx, config in enumerate(master["InstanceTypeConfigs"]):
        assert config["Priority"] == float(idx)
        assert config["WeightedCapacity"] == 1
    assert (
        master["LaunchSpecifications"]["OnDemandSpecification"]["AllocationStrategy"]
        == "prioritized"
    )


def test_declared_fleet_keeps_order_and_deduplicates_alternates():
    cfg = _fleet_base(
        core_nodes={
            "instance_types": ["r6g.2xlarge", "r7g.2xlarge", "r6i.2xlarge"],
            "target_on_demand": 2,
            "target_spot": 0,
        }
    )
    out = translate(cfg)

    core = out["Instances"]["InstanceFleets"][1]
    expected_types = [
        "r6g.2xlarge",
        "r7g.2xlarge",
        "r6i.2xlarge",
        "r6a.2xlarge",
        "r7i.2xlarge",
        "r7a.2xlarge",
    ]
    assert _instance_types(core) == expected_types
    for idx, config in enumerate(core["InstanceTypeConfigs"]):
        assert config["Priority"] == float(idx)
    assert (
        core["LaunchSpecifications"]["OnDemandSpecification"]["AllocationStrategy"]
        == "prioritized"
    )


def test_local_nvme_fleet_yields_gd_and_id_without_amd():
    cfg = _fleet_base(
        core_nodes={
            "instance_types": ["r6gd.4xlarge"],
            "target_on_demand": 1,
            "target_spot": 0,
        }
    )
    out = translate(cfg)

    core = out["Instances"]["InstanceFleets"][1]
    assert _instance_types(core) == ["r6gd.4xlarge", "r7gd.4xlarge", "r6id.4xlarge"]
    for idx, config in enumerate(core["InstanceTypeConfigs"]):
        assert config["Priority"] == float(idx)


def test_spot_fleet_allocation_strategy_defaults_and_override():
    cfg_default = _fleet_base(
        core_nodes={
            "instance_types": ["r6g.xlarge"],
            "target_on_demand": 0,
            "target_spot": 2,
        }
    )
    out_default = translate(cfg_default)
    core_default = out_default["Instances"]["InstanceFleets"][1]
    spot_spec_default = core_default["LaunchSpecifications"]["SpotSpecification"]
    assert spot_spec_default["AllocationStrategy"] == "capacity-optimized-prioritized"
    assert spot_spec_default["TimeoutAction"] == "SWITCH_TO_ON_DEMAND"

    cfg_explicit = _fleet_base(
        core_nodes={
            "instance_types": ["r6g.xlarge"],
            "target_on_demand": 0,
            "target_spot": 2,
            "allocation_strategy": "price-capacity-optimized",
        }
    )
    out_explicit = translate(cfg_explicit)
    core_explicit = out_explicit["Instances"]["InstanceFleets"][1]
    spot_spec_explicit = core_explicit["LaunchSpecifications"]["SpotSpecification"]
    assert spot_spec_explicit["AllocationStrategy"] == "price-capacity-optimized"
    assert spot_spec_explicit["TimeoutAction"] == "SWITCH_TO_ON_DEMAND"


def test_all_x86_fleet_unchanged_apart_from_priority():
    cfg = _fleet_base(
        master_node_type_id="m5.xlarge",
        core_nodes={
            "instance_types": ["m5.xlarge", "m5a.xlarge"],
            "target_on_demand": 2,
            "target_spot": 0,
        },
    )
    out = translate(cfg)
    master, core = out["Instances"]["InstanceFleets"]
    assert _instance_types(master) == ["m5.xlarge"]
    assert master["InstanceTypeConfigs"][0]["Priority"] == 0.0
    assert _instance_types(core) == ["m5.xlarge", "m5a.xlarge"]
    assert core["InstanceTypeConfigs"][0]["Priority"] == 0.0
    assert core["InstanceTypeConfigs"][1]["Priority"] == 1.0


def test_instance_group_translation_output_byte_for_byte_unchanged():
    cfg = {
        "cluster_name": "test",
        "spark_version": "emr-7.12.0",
        "master_node_type_id": "m6g.xlarge",
        "core_nodes": {"node_type_id": "r6g.2xlarge", "instance_count": 2},
        "task_nodes": {"node_type_id": "c7g.4xlarge", "instance_count": 1},
        "aws_attributes": {"availability": "ON_DEMAND"},
    }
    out = translate(cfg)
    master, core, task = out["Instances"]["InstanceGroups"]
    assert master["InstanceType"] == "m6g.xlarge"
    assert core["InstanceType"] == "r6g.2xlarge"
    assert task["InstanceType"] == "c7g.4xlarge"
    assert "InstanceFleets" not in out["Instances"]
