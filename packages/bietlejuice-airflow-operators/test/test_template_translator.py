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


def test_single_node_fleet_defaults_concurrency_to_2():
    out = translate(_fleet_base())
    assert out["StepConcurrencyLevel"] == 2
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


def test_single_node_instance_group_defaults_concurrency_to_2():
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
    assert out["StepConcurrencyLevel"] == 2
    assert len(out["Instances"]["InstanceGroups"]) == 1


def test_explicit_step_concurrency_level_wins_on_single_node():
    out = translate(_fleet_base(step_concurrency_level=3))
    assert out["StepConcurrencyLevel"] == 3


def test_emr_os_release_label_maps_to_os_release_label():
    out = translate(_fleet_base(emr_os_release_label="2023.12.20260622.0"))
    assert out["OSReleaseLabel"] == "2023.12.20260622.0"


def test_emr_os_release_label_absent_omits_os_release_label():
    out = translate(_fleet_base())
    assert "OSReleaseLabel" not in out


def test_emr_os_release_label_and_custom_ami_id_mutually_exclusive():
    with pytest.raises(ValueError, match="mutually exclusive"):
        translate(
            _fleet_base(
                emr_os_release_label="2023.12.20260622.0",
                emr_custom_ami_id="ami-0123456789abcdef0",
            )
        )


def _instance_types(fleet: dict) -> list:
    return [config["InstanceType"] for config in fleet["InstanceTypeConfigs"]]


def test_translate_does_not_mutate_the_caller_configuration():
    # translate() runs at DAG-parse and again at task-execute time on the same
    # cluster_configuration object held by the operator.
    cfg = _fleet_base()

    translate(cfg)

    assert cfg["master_node_type_id"] == "r6g.xlarge"
    assert cfg["core_nodes"]["instance_types"] == ["r6g.xlarge"]


def _spark_defaults_props(out: dict) -> dict:
    confs = out.get("Configurations") or []
    spark_defaults = next(
        (c for c in confs if c.get("Classification") == "spark-defaults"),
        None,
    )
    assert spark_defaults is not None
    return spark_defaults["Properties"]


def test_oss_delta_spark_conf_keys_are_kept_in_spark_defaults():
    # Regression: allowUnenforcedNotNull must survive spark_conf → spark-defaults
    # so DAGs do not need a custom emr_configurations list (which wipes presets).
    out = translate(
        _fleet_base(
            spark_conf={
                "spark.databricks.delta.constraints.allowUnenforcedNotNull.enabled": True,
                "spark.databricks.delta.schema.autoMerge.enabled": "true",
                "spark.databricks.delta.optimizeWrite.enabled": "true",
                "spark.sql.shuffle.partitions": "200",
            }
        )
    )
    props = _spark_defaults_props(out)
    assert (
        props["spark.databricks.delta.constraints.allowUnenforcedNotNull.enabled"]
        == "True"
    )
    assert props["spark.databricks.delta.schema.autoMerge.enabled"] == "true"
    assert props["spark.databricks.delta.optimizeWrite.enabled"] == "true"
    assert props["spark.sql.shuffle.partitions"] == "200"


def test_proprietary_delta_spark_conf_keys_are_dropped():
    # Databricks Runtime-exclusive Delta keys must not reach EMR spark-defaults.
    out = translate(
        _fleet_base(
            spark_conf={
                "spark.databricks.delta.autoCompact.enabled": "true",
                "spark.databricks.delta.merge.enableLowShuffle": "true",
            }
        )
    )
    props = _spark_defaults_props(out)
    assert props["spark.databricks.delta.autoCompact.enabled"] == "true"
    assert "spark.databricks.delta.merge.enableLowShuffle" not in props


def test_unity_catalog_spark_conf_keys_are_stripped_from_spark_defaults():
    out = translate(
        _fleet_base(
            spark_conf={
                "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod",
                "spark.sql.shuffle.partitions": "200",
            }
        )
    )
    props = _spark_defaults_props(out)
    assert "spark.databricks.sql.initial.catalog.namespace" not in props
    assert props["spark.sql.shuffle.partitions"] == "200"


def test_metrics_spark_conf_keys_are_forwarded_to_spark_defaults():
    out = translate(
        _fleet_base(
            spark_conf={
                "spark.plugins": "ch.cern.CloudFSMetrics,br.com.quintoandar.GangliaMetrics",
                "spark.metrics.conf.*.sink.graphite.host": (
                    "graphite-exporter.apps.core-frn.habitat.zone"
                ),
                "spark.databricks.foo": "bar",
            }
        )
    )
    props = _spark_defaults_props(out)
    assert (
        props["spark.plugins"]
        == "ch.cern.CloudFSMetrics,br.com.quintoandar.GangliaMetrics"
    )
    assert (
        props["spark.metrics.conf.*.sink.graphite.host"]
        == "graphite-exporter.apps.core-frn.habitat.zone"
    )
    assert "spark.databricks.foo" not in props
    assert "spark.jars.packages" not in props


def test_custom_emr_configurations_merge_with_spark_conf_delta_keys():
    # arrange — preset-like classifications must survive alongside spark_conf
    out = translate(
        _fleet_base(
            emr_configurations=[
                {
                    "Classification": "delta-defaults",
                    "Properties": {"delta.enabled": "true"},
                },
                {
                    "Classification": "spark-hive-site",
                    "Properties": {
                        "hive.metastore.client.factory.class": (
                            "com.amazonaws.glue.catalog.metastore."
                            "AWSGlueDataCatalogHiveClientFactory"
                        )
                    },
                },
            ],
            spark_conf={
                "spark.databricks.delta.constraints.allowUnenforcedNotNull.enabled": (
                    "true"
                ),
            },
        )
    )

    # assert
    classes = {c["Classification"] for c in out["Configurations"]}
    assert "delta-defaults" in classes
    assert "spark-hive-site" in classes
    assert "spark-defaults" in classes
    props = _spark_defaults_props(out)
    assert (
        props["spark.databricks.delta.constraints.allowUnenforcedNotNull.enabled"]
        == "true"
    )


SPOT_DECOMMISSION_KEYS = (
    "spark.decommission.enabled",
    "spark.storage.decommission.enabled",
    "spark.storage.decommission.shuffleBlocks.enabled",
    "spark.storage.decommission.rddBlocks.enabled",
)


def _instance_group_base(**overrides):
    cfg = {
        "cluster_name": "test",
        "spark_version": "emr-7.12.0",
        "master_node_type_id": "m5.xlarge",
        "core_nodes": {"node_type_id": "m5.xlarge", "instance_count": 2},
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


def _has_decommission_defaults(out: dict) -> bool:
    confs = out.get("Configurations") or []
    spark_defaults = next(
        (c for c in confs if c.get("Classification") == "spark-defaults"),
        None,
    )
    if spark_defaults is None:
        return False
    props = spark_defaults.get("Properties") or {}
    return all(props.get(key) == "true" for key in SPOT_DECOMMISSION_KEYS)


def test_spot_task_fleet_injects_decommission_defaults():
    out = translate(
        _fleet_base(
            core_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 2,
                "target_spot": 0,
            },
            task_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 0,
                "target_spot": 2,
            },
        )
    )

    assert _has_decommission_defaults(out)


def test_spot_core_fleet_injects_decommission_defaults():
    out = translate(
        _fleet_base(
            core_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 1,
                "target_spot": 1,
            }
        )
    )

    assert _has_decommission_defaults(out)


def test_on_demand_fleet_does_not_inject_decommission_defaults():
    out = translate(
        _fleet_base(
            core_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 2,
                "target_spot": 0,
            },
            spark_conf={"spark.sql.shuffle.partitions": "200"},
        )
    )

    props = _spark_defaults_props(out)
    assert props["spark.sql.shuffle.partitions"] == "200"
    for key in SPOT_DECOMMISSION_KEYS:
        assert key not in props


def test_spot_decommission_defaults_merge_with_existing_spark_conf():
    out = translate(
        _fleet_base(
            core_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 2,
                "target_spot": 0,
            },
            task_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 0,
                "target_spot": 1,
            },
            spark_conf={"spark.sql.shuffle.partitions": "800"},
        )
    )

    props = _spark_defaults_props(out)
    assert props["spark.sql.shuffle.partitions"] == "800"
    assert _has_decommission_defaults(out)


def test_explicit_spark_conf_wins_over_spot_decommission_defaults():
    out = translate(
        _fleet_base(
            core_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 2,
                "target_spot": 0,
            },
            task_nodes={
                "instance_types": ["r6g.xlarge"],
                "target_on_demand": 0,
                "target_spot": 1,
            },
            spark_conf={"spark.decommission.enabled": "false"},
        )
    )

    props = _spark_defaults_props(out)
    assert props["spark.decommission.enabled"] == "false"
    assert props["spark.storage.decommission.enabled"] == "true"


def test_on_demand_instance_group_does_not_inject_decommission_defaults():
    out = translate(_instance_group_base())

    assert not _has_decommission_defaults(out)
    assert "Configurations" not in out


def test_spot_task_instance_group_injects_decommission_defaults():
    out = translate(
        _instance_group_base(
            task_nodes={"node_type_id": "m5.xlarge", "instance_count": 1}
        )
    )

    assert _has_decommission_defaults(out)


def test_spot_with_fallback_core_instance_group_injects_decommission_defaults():
    out = translate(
        _instance_group_base(
            aws_attributes={
                "availability": "SPOT_WITH_FALLBACK",
                "instance_profile_arn": "arn:aws:iam::123:instance-profile/x",
            }
        )
    )

    assert _has_decommission_defaults(out)


def test_translate_fleets_instance_type_priorities():
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


def test_translate_fleets_alternates_expansion():
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


def test_translate_fleets_on_demand_specification():
    cfg = _fleet_base(
        master_node_type_id="r6g.xlarge",
        core_nodes={
            "instance_types": ["r6g.xlarge"],
            "target_on_demand": 2,
            "target_spot": 0,
        },
    )
    out = translate(cfg)
    master = out["Instances"]["InstanceFleets"][0]
    core = out["Instances"]["InstanceFleets"][1]
    assert (
        master["LaunchSpecifications"]["OnDemandSpecification"]["AllocationStrategy"]
        == "prioritized"
    )
    assert (
        core["LaunchSpecifications"]["OnDemandSpecification"]["AllocationStrategy"]
        == "prioritized"
    )


def test_translate_fleets_custom_spot_allocation_strategy():
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


def test_translate_fleets_spot_only_includes_on_demand_specification_for_timeout_fallback():
    cfg = _fleet_base(
        core_nodes={
            "instance_types": ["r6g.xlarge"],
            "target_on_demand": 0,
            "target_spot": 2,
        },
        task_nodes={
            "instance_types": ["m6g.xlarge"],
            "target_on_demand": 0,
            "target_spot": 4,
        },
    )
    out = translate(cfg)
    core = out["Instances"]["InstanceFleets"][1]
    task = out["Instances"]["InstanceFleets"][2]

    assert (
        core["LaunchSpecifications"]["OnDemandSpecification"]["AllocationStrategy"]
        == "prioritized"
    )
    assert (
        core["LaunchSpecifications"]["SpotSpecification"]["TimeoutAction"]
        == "SWITCH_TO_ON_DEMAND"
    )

    assert (
        task["LaunchSpecifications"]["OnDemandSpecification"]["AllocationStrategy"]
        == "prioritized"
    )
    assert (
        task["LaunchSpecifications"]["SpotSpecification"]["TimeoutAction"]
        == "SWITCH_TO_ON_DEMAND"
    )
