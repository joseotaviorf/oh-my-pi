#
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.
#
import copy
import logging
from typing import Tuple

from emr_plugin.constants import (
    DEFAULT_MASTER_INSTANCE_TYPE,
    DEFAULT_SPOT_TIMEOUT_MINUTES,
    EMR_FLEET_ON_DEMAND_ALLOCATION_STRATEGY,
    EMR_FLEET_SPOT_TIMEOUT_ACTION,
    EMR_INSTANCE_FLEET_NAME_CORE,
    EMR_INSTANCE_FLEET_NAME_MASTER,
    EMR_INSTANCE_FLEET_NAME_TASK,
    EMR_INSTANCE_GROUP_NAME_CORE,
    EMR_INSTANCE_GROUP_NAME_MASTER,
    EMR_INSTANCE_GROUP_NAME_TASK,
    SPOT_DECOMMISSION_PROPERTIES,
)
from emr_plugin.instance_alternates import with_alternates

log = logging.getLogger(__name__)

EBS_VOLUME_TYPE_MAP = {
    "GENERAL_PURPOSE_SSD": "gp2",
    "THROUGHPUT_OPTIMIZED_HDD": "st1",
    "GENERAL_PURPOSE_SSD_GP3": "gp3",
    "gp2": "gp2",
    "gp3": "gp3",
    "io1": "io1",
    "st1": "st1",
}

# Master is always ON_DEMAND; availability controls CORE market only.
AVAILABILITY_MAP = {
    "SPOT": "SPOT",
    "SPOT_WITH_FALLBACK": "SPOT",
    "ON_DEMAND": "ON_DEMAND",
}
MASTER_MARKET = "ON_DEMAND"

DEFAULT_STEP_CONCURRENCY_LEVEL = 4
# Master-only clusters share one node's YARN AM budget. Allow two concurrent
# steps so CDC-style overlap (optimize layer N + load layer N+1) can proceed
# when YARN capacity permits; YARN may queue the second application on the
# smallest tier. Keep this aligned with step_concurrency_level on single-node
# presets in prod_conf/forno_conf.
SINGLE_NODE_STEP_CONCURRENCY_LEVEL = 2

TASK_AVAILABILITY_MAP = {"SPOT": "SPOT", "ON_DEMAND": "ON_DEMAND"}
DEFAULT_TASK_MARKET = "SPOT"

# Only keys that are popped in translate() or _translate_*() are consumed.
# Any other key in config (unknown, Databricks-only, deprecated) is dropped
# at the end so new or extra YAML fields never break the translator.
#
# Strip Databricks-only spark_conf keys, but keep OSS Delta settings that still
# use the historical ``spark.databricks.delta.*`` prefix (e.g. allowUnenforcedNotNull,
# schema.autoMerge). Putting those solely under custom ``emr_configurations`` is
# unsafe: HierarchicalConf deep-merge replaces list values wholesale and wipes
# preset Glue/Delta classifications.
DATABRICKS_SPARK_CONF_PREFIXES = ("spark.databricks.",)
OSS_DELTA_SPARK_CONF_PREFIX = "spark.databricks.delta."
# Delta-prefixed but absent from Delta OSS 3.3.x DeltaSQLConf — Databricks
# Runtime only, so forwarding it to EMR is a silent no-op. Mirrors
# bietlejuice-core base/validation/cluster_args.py; this package intentionally
# has no bietlejuice dependency (Airflow plugin entry-points).
DATABRICKS_PROPRIETARY_DELTA_SPARK_CONF_KEYS = frozenset(
    {"spark.databricks.delta.merge.enableLowShuffle"}
)


def _is_stripped_databricks_spark_conf(key: str) -> bool:
    """Return True when ``key`` must be dropped from spark_conf → spark-defaults."""
    if key in DATABRICKS_PROPRIETARY_DELTA_SPARK_CONF_KEYS:
        return True
    if key.startswith(OSS_DELTA_SPARK_CONF_PREFIX):
        return False
    return any(key.startswith(prefix) for prefix in DATABRICKS_SPARK_CONF_PREFIXES)


# Legacy scalar keys that only make sense for instance groups. These must never
# be silently dropped once core_nodes/task_nodes switch to instance-fleet shape.
_LEGACY_GROUP_ONLY_KEYS = (
    "node_type_id",
    "num_workers",
    "num_task_workers",
    "task_node_type_id",
)
_GROUP_ONLY_BLOCK_KEYS = frozenset({"node_type_id", "instance_count"})
_FLEET_ONLY_BLOCK_KEYS = frozenset(
    {
        "target_on_demand",
        "target_spot",
        "allocation_strategy",
        "instance_types",
        "bid_price_percentage",
        "spot_timeout_minutes",
    }
)


def translate(config: dict) -> dict:
    """
    Translates a cluster configuration dict (YAML template format) into an
    EMR ``job_flow_overrides`` dict compatible with ``EmrCreateJobFlowOperator``.

    :param config: Cluster configuration in the YAML template format.
    :return: EMR job_flow_overrides dict.
    """
    cfg = copy.deepcopy(config)

    overrides = {}

    overrides["Name"] = cfg.pop("cluster_name", "emr-cluster")

    spark_version = cfg.pop("spark_version", None)
    if spark_version:
        overrides["ReleaseLabel"] = spark_version

    os_release_label = cfg.pop("emr_os_release_label", None)
    custom_ami_id = cfg.pop("emr_custom_ami_id", None)
    if os_release_label and custom_ami_id:
        raise ValueError(
            "emr_os_release_label and emr_custom_ami_id are mutually exclusive; "
            "use one or the other"
        )
    if os_release_label:
        overrides["OSReleaseLabel"] = str(os_release_label)
    if custom_ami_id:
        overrides["CustomAmiId"] = str(custom_ami_id)

    _translate_log_conf(cfg, overrides)
    _translate_applications(cfg, overrides)
    _translate_roles(cfg, overrides)
    if _uses_instance_fleets(cfg):
        _translate_instance_fleets(cfg, overrides)
    else:
        _translate_instances(cfg, overrides)
    _translate_tags(cfg, overrides)
    _translate_bootstrap_actions(cfg, overrides)
    _translate_configurations(cfg, overrides)
    _translate_auto_termination(cfg, overrides)

    ebs_root_volume_size = cfg.pop("emr_ebs_root_volume_size", None)
    if ebs_root_volume_size is not None:
        overrides["EbsRootVolumeSize"] = int(ebs_root_volume_size)

    configured_concurrency = cfg.pop("step_concurrency_level", None)
    if configured_concurrency is not None:
        overrides["StepConcurrencyLevel"] = int(configured_concurrency)
    elif _is_single_node(overrides):
        overrides["StepConcurrencyLevel"] = SINGLE_NODE_STEP_CONCURRENCY_LEVEL
    else:
        overrides["StepConcurrencyLevel"] = DEFAULT_STEP_CONCURRENCY_LEVEL

    for field in list(cfg.keys()):
        cfg.pop(field)

    return overrides


def _translate_log_conf(cfg: dict, overrides: dict):
    log_conf = cfg.pop("cluster_log_conf", None)
    if log_conf:
        s3_conf = log_conf.get("s3", {})
        destination = s3_conf.get("destination")
        if destination:
            overrides["LogUri"] = destination


def _translate_applications(cfg: dict, overrides: dict):
    apps = cfg.pop("emr_applications", ["Spark"])
    overrides["Applications"] = [{"Name": app} for app in apps]


def _build_scaling_rule(rule: dict) -> dict:
    action_cfg = rule.get("action", {})
    trigger_cfg = rule.get("trigger", {})
    emr_rule = {
        "Name": rule.get("name", "scaling-rule"),
        "Action": {
            "SimpleScalingPolicyConfiguration": {
                "AdjustmentType": action_cfg.get(
                    "adjustment_type", "CHANGE_IN_CAPACITY"
                ),
                "ScalingAdjustment": int(action_cfg.get("scaling_adjustment", 1)),
                "CoolDown": int(action_cfg.get("cool_down", 300)),
            }
        },
        "Trigger": {
            "CloudWatchAlarmDefinition": {
                "ComparisonOperator": trigger_cfg.get(
                    "comparison_operator", "LESS_THAN"
                ),
                "MetricName": trigger_cfg.get(
                    "metric_name", "YARNMemoryAvailablePercentage"
                ),
                "Namespace": trigger_cfg.get("namespace", "AWS/ElasticMapReduce"),
                "Period": int(trigger_cfg.get("period", 300)),
                "Statistic": trigger_cfg.get("statistic", "AVERAGE"),
                "Threshold": float(trigger_cfg.get("threshold", 15.0)),
                "Unit": trigger_cfg.get("unit", "PERCENT"),
            }
        },
    }
    dimensions = trigger_cfg.get("dimensions")
    if dimensions:
        emr_rule["Trigger"]["CloudWatchAlarmDefinition"]["Dimensions"] = [
            {"Key": d["key"], "Value": d["value"]} for d in dimensions
        ]
    return emr_rule


def _build_autoscaling_policy(
    min_capacity: int, max_capacity: int, rules: list
) -> dict:
    return {
        "Constraints": {"MinCapacity": min_capacity, "MaxCapacity": max_capacity},
        "Rules": [_build_scaling_rule(rule) for rule in rules],
    }


def _core_worker_count(total_workers: int, num_task_workers: int) -> int:
    return int(total_workers) - int(num_task_workers)


def _task_market(aws_attrs: dict) -> str:
    task_availability = aws_attrs.get("task_availability", DEFAULT_TASK_MARKET)
    return TASK_AVAILABILITY_MAP.get(task_availability, DEFAULT_TASK_MARKET)


def _resolve_master_instance_type(cfg: dict) -> str:
    """Resolve YARN master instance type from EMR cluster config."""
    master_type = cfg.pop("master_node_type_id", None)
    driver_type = cfg.pop("driver_node_type_id", None)
    if master_type is not None:
        if driver_type is not None and driver_type != master_type:
            log.warning(
                "Both master_node_type_id (%s) and driver_node_type_id (%s) set; "
                "using master_node_type_id.",
                master_type,
                driver_type,
            )
        return master_type
    if driver_type is not None:
        log.info(
            "driver_node_type_id is deprecated for EMR clusters; "
            "use master_node_type_id instead."
        )
        return driver_type
    return DEFAULT_MASTER_INSTANCE_TYPE


def _resolve_worker_topology(cfg: dict) -> Tuple[str, int, str, int]:
    """Return (core_type, core_count, task_type, task_count) for instance groups."""
    core_block = cfg.pop("core_nodes", None)
    task_block = cfg.pop("task_nodes", None)

    legacy_worker_type = cfg.pop("node_type_id", None)
    legacy_num_workers = cfg.pop("num_workers", None)
    legacy_num_task = cfg.pop("num_task_workers", None)
    legacy_task_type = cfg.pop("task_node_type_id", None)

    if isinstance(core_block, dict):
        core_type = core_block.get("node_type_id") or legacy_worker_type or "m5.xlarge"
        if "instance_count" in core_block:
            core_count = int(core_block.get("instance_count", 0) or 0)
        else:
            core_count = 0
    else:
        if legacy_worker_type is not None or legacy_num_workers is not None:
            log.info(
                "node_type_id/num_workers are deprecated for EMR clusters; "
                "use core_nodes and task_nodes instead."
            )
        num_workers = int(legacy_num_workers if legacy_num_workers is not None else 1)
        num_task_workers = int(legacy_num_task or 0)
        core_type = legacy_worker_type or "m5.xlarge"
        if legacy_num_workers is not None and num_workers == 0:
            core_count = 0
        else:
            core_count = _core_worker_count(num_workers, num_task_workers)

    if isinstance(task_block, dict):
        task_type = task_block.get("node_type_id") or legacy_task_type or core_type
        task_count = int(task_block.get("instance_count", 0) or 0)
    else:
        if legacy_num_task is not None:
            task_count = int(legacy_num_task or 0)
        else:
            task_count = 0
        task_type = legacy_task_type or core_type

    return core_type, core_count, task_type, task_count


def _is_single_node(overrides: dict) -> bool:
    """True when the translated cluster has only a master fleet/group."""
    instances = overrides.get("Instances") or {}
    nodes = instances.get("InstanceFleets") or instances.get("InstanceGroups") or []
    return len(nodes) == 1


def _uses_spot_capacity(overrides: dict) -> bool:
    """True when any worker fleet/group in the translated request uses spot."""
    instances = overrides.get("Instances") or {}
    for fleet in instances.get("InstanceFleets") or []:
        if int(fleet.get("TargetSpotCapacity") or 0) > 0:
            return True
    for group in instances.get("InstanceGroups") or []:
        if group.get("Market") == "SPOT" and int(group.get("InstanceCount") or 0) > 0:
            return True
    return False


def _spark_defaults_block(configurations: list) -> dict:
    existing = next(
        (c for c in configurations if c.get("Classification") == "spark-defaults"),
        None,
    )
    if existing is not None:
        existing.setdefault("Properties", {})
        return existing
    block = {"Classification": "spark-defaults", "Properties": {}}
    configurations.append(block)
    return block


def _inject_spot_decommission(configurations: list, overrides: dict) -> None:
    """Merge Spark decommission defaults when the cluster has spot workers.

    Uses setdefault so an explicit spark-defaults / spark_conf value wins.
    """
    if not _uses_spot_capacity(overrides):
        return
    props = _spark_defaults_block(configurations)["Properties"]
    for key, value in SPOT_DECOMMISSION_PROPERTIES.items():
        props.setdefault(key, value)


def _is_fleet_block(block) -> bool:
    """True if a core_nodes/task_nodes block is fleet-shaped (has instance_types)."""
    return isinstance(block, dict) and "instance_types" in block


def _check_no_mixed_block_keys(block, name: str) -> None:
    if not isinstance(block, dict):
        return
    group_keys = _GROUP_ONLY_BLOCK_KEYS.intersection(block.keys())
    fleet_keys = _FLEET_ONLY_BLOCK_KEYS.intersection(block.keys())
    if group_keys and fleet_keys:
        raise ValueError(
            f"'{name}' mixes instance-group keys {sorted(group_keys)} with "
            f"instance-fleet keys {sorted(fleet_keys)}; use one style or the other, "
            "not both"
        )


def _uses_instance_fleets(cfg: dict) -> bool:
    """Detect fleet mode and fail fast on any group/fleet mixing, rather than
    letting the translator silently drop the config it doesn't expect."""
    core_block = cfg.get("core_nodes")
    task_block = cfg.get("task_nodes")
    _check_no_mixed_block_keys(core_block, "core_nodes")
    _check_no_mixed_block_keys(task_block, "task_nodes")

    core_is_fleet = _is_fleet_block(core_block)
    task_is_fleet = _is_fleet_block(task_block)
    if not (core_is_fleet or task_is_fleet):
        return False

    core_is_group = isinstance(core_block, dict) and core_block and not core_is_fleet
    task_is_group = isinstance(task_block, dict) and task_block and not task_is_fleet
    if core_is_group or task_is_group:
        raise ValueError(
            "core_nodes and task_nodes must both use instance groups or both use "
            "instance fleets (AWS EMR does not allow mixing InstanceGroups and "
            "InstanceFleets in one cluster)"
        )

    legacy_keys_present = [
        key for key in _LEGACY_GROUP_ONLY_KEYS if cfg.get(key) is not None
    ]
    if legacy_keys_present:
        raise ValueError(
            f"Legacy instance-group keys {legacy_keys_present} cannot be combined "
            "with instance-fleet core_nodes/task_nodes; remove them or switch back "
            "to instance groups"
        )
    return True


def _resolve_fleet_topology(cfg: dict) -> Tuple[dict, dict]:
    """Pop and normalize core_nodes/task_nodes fleet blocks.

    Returns (core_fleet_spec, task_fleet_spec); either is {} if absent or has no
    target capacity.
    """
    core_block = cfg.pop("core_nodes", None) or {}
    task_block = cfg.pop("task_nodes", None) or {}

    def _normalize(block: dict) -> dict:
        if not block:
            return {}
        target_on_demand = int(block.get("target_on_demand", 0) or 0)
        target_spot = int(block.get("target_spot", 0) or 0)
        if target_on_demand == 0 and target_spot == 0:
            return {}
        return {
            "instance_types": list(block.get("instance_types") or []),
            "target_on_demand": target_on_demand,
            "target_spot": target_spot,
            "allocation_strategy": block.get("allocation_strategy"),
            "bid_price_percentage": block.get("bid_price_percentage"),
            "spot_timeout_minutes": int(
                block.get("spot_timeout_minutes", DEFAULT_SPOT_TIMEOUT_MINUTES)
            ),
        }

    return _normalize(core_block), _normalize(task_block)


def _build_instance_type_configs(
    instance_types: list, ebs_config: dict = None, bid_price_percentage=None
) -> list:
    configs = []
    expanded_types = with_alternates(instance_types)
    for index, instance_type in enumerate(expanded_types):
        entry = {
            "InstanceType": instance_type,
            "WeightedCapacity": 1,
            "Priority": float(index),
        }
        if bid_price_percentage is not None:
            entry["BidPriceAsPercentageOfOnDemandPrice"] = bid_price_percentage
        if ebs_config:
            entry["EbsConfiguration"] = copy.deepcopy(ebs_config)
        configs.append(entry)
    return configs


def _build_spot_specification(spec: dict) -> dict:
    strategy = spec.get("allocation_strategy") or "capacity-optimized-prioritized"
    launch_spec = {
        "TimeoutDurationMinutes": spec["spot_timeout_minutes"],
        "TimeoutAction": EMR_FLEET_SPOT_TIMEOUT_ACTION,
        "AllocationStrategy": strategy,
    }
    return {"SpotSpecification": launch_spec}


def _build_on_demand_specification() -> dict:
    return {
        "OnDemandSpecification": {
            "AllocationStrategy": EMR_FLEET_ON_DEMAND_ALLOCATION_STRATEGY,
        }
    }


def _translate_instance_fleets(cfg: dict, overrides: dict):
    master_instance_type = _resolve_master_instance_type(cfg)
    core_spec, task_spec = _resolve_fleet_topology(cfg)

    autoscale = cfg.pop("autoscale", None)
    if autoscale and isinstance(autoscale, dict):
        raise ValueError(
            "autoscale is not supported with EMR Instance Fleets (core_nodes/"
            "task_nodes use instance_types); use target_on_demand/target_spot "
            "instead, or switch back to group-style core_nodes/task_nodes"
        )

    if task_spec and not core_spec:
        raise ValueError(
            "task_nodes cannot have fleet capacity (target_on_demand/target_spot "
            "> 0) while core_nodes has none; EMR requires at least one CORE "
            "instance fleet with capacity"
        )

    aws_attrs = cfg.pop("aws_attributes", {})
    if aws_attrs.get("spot_bid_price"):
        log.warning(
            "aws_attributes.spot_bid_price is ignored in fleet mode; use "
            "core_nodes.bid_price_percentage / task_nodes.bid_price_percentage "
            "instead."
        )

    ebs_volume_size = aws_attrs.get("ebs_volume_size")
    ebs_volume_type = aws_attrs.get("ebs_volume_type", "GENERAL_PURPOSE_SSD")
    ebs_volume_count = aws_attrs.get("ebs_volume_count", 1)

    ebs_config = None
    if ebs_volume_size:
        mapped_type = EBS_VOLUME_TYPE_MAP.get(ebs_volume_type, "gp2")
        ebs_config = {
            "EbsBlockDeviceConfigs": [
                {
                    "VolumeSpecification": {
                        "VolumeType": mapped_type,
                        "SizeInGB": int(ebs_volume_size),
                    },
                    "VolumesPerInstance": int(ebs_volume_count),
                }
            ]
        }

    master_fleet = {
        "Name": EMR_INSTANCE_FLEET_NAME_MASTER,
        "InstanceFleetType": "MASTER",
        "TargetOnDemandCapacity": 1,
        "TargetSpotCapacity": 0,
        "InstanceTypeConfigs": _build_instance_type_configs(
            [master_instance_type], ebs_config=ebs_config
        ),
        "LaunchSpecifications": _build_on_demand_specification(),
    }

    fleets = [master_fleet]

    if core_spec:
        core_fleet = {
            "Name": EMR_INSTANCE_FLEET_NAME_CORE,
            "InstanceFleetType": "CORE",
            "TargetOnDemandCapacity": core_spec["target_on_demand"],
            "TargetSpotCapacity": core_spec["target_spot"],
            "InstanceTypeConfigs": _build_instance_type_configs(
                core_spec["instance_types"],
                ebs_config=ebs_config,
                bid_price_percentage=core_spec["bid_price_percentage"],
            ),
        }
        # Always configure OnDemandSpecification with 'prioritized' allocation strategy.
        # This ensures Priority is respected not only when target_on_demand > 0, but also
        # when Spot capacity times out and switches to On-Demand (SWITCH_TO_ON_DEMAND).
        core_launch_specs = _build_on_demand_specification()
        if core_spec["target_spot"] > 0:
            core_launch_specs.update(_build_spot_specification(core_spec))
        core_fleet["LaunchSpecifications"] = core_launch_specs
        fleets.append(core_fleet)

    if task_spec:
        task_fleet = {
            "Name": EMR_INSTANCE_FLEET_NAME_TASK,
            "InstanceFleetType": "TASK",
            "TargetOnDemandCapacity": task_spec["target_on_demand"],
            "TargetSpotCapacity": task_spec["target_spot"],
            "InstanceTypeConfigs": _build_instance_type_configs(
                task_spec["instance_types"],
                ebs_config=ebs_config,
                bid_price_percentage=task_spec["bid_price_percentage"],
            ),
        }
        # Always configure OnDemandSpecification with 'prioritized' allocation strategy
        # so fallback On-Demand launches on Spot timeout honour ARM-first Priority.
        task_launch_specs = _build_on_demand_specification()
        if task_spec["target_spot"] > 0:
            task_launch_specs.update(_build_spot_specification(task_spec))
        task_fleet["LaunchSpecifications"] = task_launch_specs
        fleets.append(task_fleet)

    instances = {"InstanceFleets": fleets, "KeepJobFlowAliveWhenNoSteps": True}

    subnet_id = cfg.pop("emr_subnet_id", None)
    if subnet_id:
        instances["Ec2SubnetId"] = subnet_id

    security_groups = cfg.pop("emr_security_groups", None)
    if security_groups:
        if "master" in security_groups:
            instances["EmrManagedMasterSecurityGroup"] = security_groups["master"]
        if "slave" in security_groups:
            instances["EmrManagedSlaveSecurityGroup"] = security_groups["slave"]

    overrides["Instances"] = instances


def _translate_instances(cfg: dict, overrides: dict):
    master_instance_type = _resolve_master_instance_type(cfg)
    core_type, core_count, task_type, task_count = _resolve_worker_topology(cfg)
    autoscale = cfg.pop("autoscale", None)
    total_workers = core_count + task_count
    aws_attrs = cfg.pop("aws_attributes", {})

    availability = aws_attrs.get("availability", "SPOT_WITH_FALLBACK")
    core_market = AVAILABILITY_MAP.get(availability, "SPOT")
    master_market = MASTER_MARKET
    task_market = _task_market(aws_attrs)
    spot_bid_price = aws_attrs.get("spot_bid_price")

    ebs_volume_size = aws_attrs.get("ebs_volume_size")
    ebs_volume_type = aws_attrs.get("ebs_volume_type", "GENERAL_PURPOSE_SSD")
    ebs_volume_count = aws_attrs.get("ebs_volume_count", 1)

    master_group = {
        "Name": EMR_INSTANCE_GROUP_NAME_MASTER,
        "Market": master_market,
        "InstanceRole": "MASTER",
        "InstanceType": master_instance_type,
        "InstanceCount": 1,
    }

    autoscale_policy = None
    if autoscale and isinstance(autoscale, dict):
        if core_count == 0 and task_count == 0:
            raise ValueError(
                "autoscale cannot be used on a master-only EMR cluster "
                "(core_nodes.instance_count=0 and no task_nodes)"
            )
        min_workers = int(autoscale.get("min_workers", total_workers))
        max_workers = int(autoscale.get("max_workers", min_workers))
        core_min = max(0, _core_worker_count(min_workers, task_count))
        core_max = max(core_min, _core_worker_count(max_workers, task_count))
        if core_min == 0 and core_max == 0:
            core_instance_count = 0
        else:
            core_min = max(1, core_min)
            core_max = max(core_min, core_max)
            core_instance_count = core_min
        rules = autoscale.get("rules")
        if rules and core_instance_count > 0:
            autoscale_policy = _build_autoscaling_policy(core_min, core_max, rules)
            overrides["AutoScalingRole"] = cfg.pop(
                "emr_auto_scaling_role", "EMR_AutoScaling_DefaultRole"
            )
        elif core_instance_count > 0:
            overrides["ManagedScalingPolicy"] = {
                "ComputeLimits": {
                    "UnitType": "Instances",
                    "MinimumCapacityUnits": core_min,
                    "MaximumCapacityUnits": core_max,
                    "MaximumOnDemandCapacityUnits": core_max,
                    "MaximumCoreCapacityUnits": core_max,
                }
            }
    else:
        core_instance_count = core_count

    ebs_config = None
    if ebs_volume_size:
        mapped_type = EBS_VOLUME_TYPE_MAP.get(ebs_volume_type, "gp2")
        ebs_config = {
            "EbsBlockDeviceConfigs": [
                {
                    "VolumeSpecification": {
                        "VolumeType": mapped_type,
                        "SizeInGB": int(ebs_volume_size),
                    },
                    "VolumesPerInstance": int(ebs_volume_count),
                }
            ]
        }
        master_group["EbsConfiguration"] = ebs_config

    instance_groups = [master_group]
    if core_instance_count > 0:
        core_group = {
            "Name": EMR_INSTANCE_GROUP_NAME_CORE,
            "Market": core_market,
            "InstanceRole": "CORE",
            "InstanceType": core_type,
            "InstanceCount": core_instance_count,
        }
        if autoscale_policy:
            core_group["AutoScalingPolicy"] = autoscale_policy
        if ebs_config:
            core_group["EbsConfiguration"] = copy.deepcopy(ebs_config)

        instance_groups.append(core_group)
    if task_count > 0:
        task_group = {
            "Name": EMR_INSTANCE_GROUP_NAME_TASK,
            "Market": task_market,
            "InstanceRole": "TASK",
            "InstanceType": task_type,
            "InstanceCount": task_count,
        }
        if spot_bid_price and task_market == "SPOT":
            task_group["BidPrice"] = str(spot_bid_price)
        if ebs_config:
            task_group["EbsConfiguration"] = copy.deepcopy(ebs_config)
        instance_groups.append(task_group)

    instances = {"InstanceGroups": instance_groups, "KeepJobFlowAliveWhenNoSteps": True}

    subnet_id = cfg.pop("emr_subnet_id", None)
    if subnet_id:
        instances["Ec2SubnetId"] = subnet_id

    security_groups = cfg.pop("emr_security_groups", None)
    if security_groups:
        if "master" in security_groups:
            instances["EmrManagedMasterSecurityGroup"] = security_groups["master"]
        if "slave" in security_groups:
            instances["EmrManagedSlaveSecurityGroup"] = security_groups["slave"]

    overrides["Instances"] = instances


def _translate_roles(cfg: dict, overrides: dict):
    aws_attrs = cfg.get("aws_attributes", {})
    instance_profile = aws_attrs.get("instance_profile_arn")

    job_flow_role = cfg.pop("emr_job_flow_role", None) or instance_profile
    if job_flow_role:
        overrides["JobFlowRole"] = job_flow_role

    service_role = cfg.pop("emr_service_role", None)
    if service_role:
        overrides["ServiceRole"] = service_role


def _translate_tags(cfg: dict, overrides: dict):
    custom_tags = cfg.pop("custom_tags", None)
    if custom_tags:
        overrides["Tags"] = [
            {
                "Key": tag.get("key", tag.get("Key", "")),
                "Value": tag.get("value", tag.get("Value", "")),
            }
            for tag in custom_tags
        ]


def _translate_bootstrap_actions(cfg: dict, overrides: dict):
    init_scripts = cfg.pop("init_scripts", None)
    if not init_scripts:
        return

    actions = []
    for i, script in enumerate(init_scripts):
        s3_info = script.get("s3", {})
        path = s3_info.get("destination", "")
        if path:
            name = path.rsplit("/", 1)[-1] if "/" in path else f"bootstrap_{i}"
            script_action = {"Path": path}
            args = script.get("args")
            if args is not None:
                script_action["Args"] = [str(a) for a in args]
            actions.append({"Name": name, "ScriptBootstrapAction": script_action})
    if actions:
        overrides["BootstrapActions"] = actions


def _translate_configurations(cfg: dict, overrides: dict):
    configurations = []

    extra_confs = cfg.pop("emr_configurations", None) or []
    spark_hive_site = [
        c for c in extra_confs if c.get("Classification") == "spark-hive-site"
    ]
    other_confs = [
        c for c in extra_confs if c.get("Classification") != "spark-hive-site"
    ]
    configurations.extend(other_confs)

    spark_conf = cfg.pop("spark_conf", None)
    if spark_conf:
        filtered = {
            k: str(v)
            for k, v in spark_conf.items()
            if not _is_stripped_databricks_spark_conf(k)
        }
        if filtered:
            existing = next(
                (c for c in configurations if c["Classification"] == "spark-defaults"),
                None,
            )
            if existing:
                existing.setdefault("Properties", {}).update(filtered)
            else:
                configurations.append(
                    {"Classification": "spark-defaults", "Properties": filtered}
                )

    _inject_spot_decommission(configurations, overrides)

    spark_env = cfg.pop("spark_env_vars", None)
    if spark_env:
        configurations.append(
            {
                "Classification": "spark-env",
                "Configurations": [
                    {
                        "Classification": "export",
                        "Properties": {k: str(v) for k, v in spark_env.items()},
                    }
                ],
            }
        )

    configurations.extend(spark_hive_site)

    if configurations:
        overrides["Configurations"] = configurations


def _translate_auto_termination(cfg: dict, overrides: dict):
    minutes = cfg.pop("autotermination_minutes", None)
    if minutes:
        overrides["AutoTerminationPolicy"] = {"IdleTimeout": int(minutes) * 60}
