import pytest
from emr_plugin.template_translator import translate


def _fleet_base(**overrides):
    cfg = {
        "cluster_name": "test",
        "spark_version": "emr-7.12.0",
        "master_node_type_id": "r6g.xlarge",
        "core_nodes": {
            "instance_types": ["r6g.xlarge"],
            "target_on_demand": 0,
            "target_spot": 0,
        },
        "task_nodes": {
            "instance_types": ["r6g.xlarge"],
            "target_on_demand": 0,
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
    cfg.update(overrides)
    return cfg


def test_single_node_fleet_defaults_concurrency_to_1():
    out = translate(_fleet_base())
    assert out["StepConcurrencyLevel"] == 1
    assert len(out["Instances"]["InstanceFleets"]) == 1


def test_multi_node_fleet_defaults_concurrency_to_4():
    out = translate(
        _fleet_base(
            core_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 2,
                "target_spot": 0,
            }
        )
    )
    assert out["StepConcurrencyLevel"] == 4
    assert len(out["Instances"]["InstanceFleets"]) == 2


def test_single_node_instance_group_defaults_concurrency_to_1():
    out = translate(
        {
            "cluster_name": "test",
            "spark_version": "emr-7.12.0",
            "master_node_type_id": "m5.xlarge",
            "core_nodes": {"node_type_id": "m5.xlarge", "instance_count": 0},
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
    )
    assert out["StepConcurrencyLevel"] == 1
    assert len(out["Instances"]["InstanceGroups"]) == 1


def test_explicit_step_concurrency_level_wins_on_single_node():
    out = translate(_fleet_base(step_concurrency_level=3))
    assert out["StepConcurrencyLevel"] == 3


def test_emr_os_release_label_maps_to_os_release_label():
    out = translate(_fleet_base(emr_os_release_label="2023.12.20260629.0"))
    assert out["OSReleaseLabel"] == "2023.12.20260629.0"


def test_emr_os_release_label_absent_omits_os_release_label():
    out = translate(_fleet_base())
    assert "OSReleaseLabel" not in out


def test_emr_os_release_label_and_custom_ami_id_mutually_exclusive():
    with pytest.raises(ValueError, match="mutually exclusive"):
        translate(
            _fleet_base(
                emr_os_release_label="2023.12.20260629.0",
                emr_custom_ami_id="ami-0123456789abcdef0",
            )
        )
