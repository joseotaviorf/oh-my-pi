import json

from cerberus import Validator

from bietlejuice.base.airflow.cluster_config_resolver import is_airflow_emr_cluster
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)

_EMR_TASK_AVAILABILITY_VALUES = frozenset({"SPOT", "ON_DEMAND"})
_EMR_ONLY_CUSTOM_CONFIG_KEYS = frozenset(
    {
        "num_task_workers",
        "task_node_type_id",
        "task_availability",
        "core_nodes",
        "task_nodes",
    }
)
_EMR_FLEET_ALLOCATION_STRATEGIES = frozenset(
    {"price-capacity-optimized", "capacity-optimized", "lowest-price", "diversified"}
)
# Legacy scalar keys that only make sense for instance groups. These must never
# be silently ignored once core_nodes/task_nodes switch to instance-fleet shape.
_LEGACY_GROUP_ONLY_KEYS = frozenset(
    {"node_type_id", "num_workers", "num_task_workers", "task_node_type_id"}
)
_GROUP_ONLY_NODE_BLOCK_KEYS = frozenset({"node_type_id", "instance_count"})
_FLEET_ONLY_NODE_BLOCK_KEYS = frozenset(
    {
        "target_on_demand",
        "target_spot",
        "allocation_strategy",
        "instance_types",
        "bid_price_percentage",
        "spot_timeout_minutes",
        "max_nodes",
    }
)


class DAGClusterValidator(Validator):
    """Cerberus validation rules for the DAG declaration ``cluster`` section."""

    __SCHEMA = {
        "type": "dict",
        "allow_unknown": False,
        "required": True,
        "empty": False,
        "schema": {
            "type": {"type": "string", "required": True, "empty": False},
            "custom_configurations": {
                "type": "dict",
                "required": False,
                "empty": False,
            },
            "custom_libraries": {"type": "list", "required": False, "empty": False},
            "access_control_list": {
                "empty": False,
                "anyof": [
                    {
                        "type": "dict",
                        "schema": {
                            "group_name": {
                                "type": "string",
                                "empty": False,
                                "allowed": DatabricksGroupNameEnum.get_available_enum_values(),
                            },
                            "permission_level": {
                                "type": "string",
                                "empty": False,
                                "allowed": ClusterPermissionEnum.get_available_enum_values(),
                            },
                        },
                    },
                    {
                        "type": "list",
                        "schema": {
                            "type": "dict",
                            "schema": {
                                "group_name": {
                                    "type": "string",
                                    "empty": False,
                                    "allowed": DatabricksGroupNameEnum.get_available_enum_values(),
                                },
                                "permission_level": {
                                    "type": "string",
                                    "empty": False,
                                    "allowed": ClusterPermissionEnum.get_available_enum_values(),
                                },
                            },
                        },
                    },
                ],
            },
            "databricks_conn_id": {"type": "string", "empty": False},
            "emr_task_retries": {"type": "integer", "min": 0, "required": False},
            "emr_retry_delay_seconds": {
                "type": "integer",
                "min": 0,
                "required": False,
            },
        },
    }

    __ROOT_WRAPPER_SCHEMA = {"cluster": __SCHEMA}

    def validate_cluster(self, dag_declaration: dict) -> None:
        """
        Validates only the ``cluster`` section of a DAG declaration.

        Args:
            dag_declaration: Parsed DAG declaration (only ``cluster`` is read).

        Raises:
            AssertionError: If cluster validation fails.
        """
        super().validate(
            {"cluster": dag_declaration.get("cluster")},
            schema=self.__ROOT_WRAPPER_SCHEMA,
        )
        if self.errors:
            raise AssertionError(
                "m=validate_cluster, msg=One or more cluster validation rules had errors:\n",
                f"{json.dumps(self.errors, indent=2)}",
            )

        self._check_emr_cluster_configuration(dag_declaration.get("cluster", {}))

    @staticmethod
    def _is_emr_cluster_declaration(cluster: dict) -> bool:
        cluster_type = cluster.get("type", "")
        if isinstance(cluster_type, str) and cluster_type.startswith("emr_"):
            return True
        custom = cluster.get("custom_configurations") or {}
        spark_version = custom.get("spark_version", "")
        return is_airflow_emr_cluster(str(spark_version))

    def _check_emr_cluster_configuration(self, cluster: dict) -> None:
        if not cluster:
            return

        custom = cluster.get("custom_configurations") or {}
        if not isinstance(custom, dict):
            return

        is_emr = self._is_emr_cluster_declaration(cluster)
        aws_attrs = custom.get("aws_attributes") or {}
        if not isinstance(aws_attrs, dict):
            aws_attrs = {}

        emr_only_in_custom = _EMR_ONLY_CUSTOM_CONFIG_KEYS.intersection(custom.keys())
        task_availability = aws_attrs.get("task_availability")
        if task_availability is not None:
            emr_only_in_custom = emr_only_in_custom | {"task_availability"}

        if not is_emr:
            if emr_only_in_custom:
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg=EMR-only cluster keys in custom_configurations: "
                    f"{sorted(emr_only_in_custom)}"
                )
            return

        core_nodes = custom.get("core_nodes")
        task_nodes = custom.get("task_nodes")
        if core_nodes is not None or task_nodes is not None:
            self._assert_emr_node_group(core_nodes, "core_nodes", min_count=0)
            core_is_fleet = self._is_emr_fleet_block(core_nodes)
            task_is_fleet = False
            if task_nodes is not None:
                self._assert_emr_node_group(task_nodes, "task_nodes", min_count=0)
                task_is_fleet = self._is_emr_fleet_block(task_nodes)

                if core_nodes is not None and core_is_fleet != task_is_fleet:
                    raise AssertionError(
                        "m=_check_emr_cluster_configuration, "
                        "msg='core_nodes' and 'task_nodes' must both use instance "
                        "groups or both use instance fleets (AWS EMR does not "
                        "support mixing InstanceGroups and InstanceFleets in one "
                        "cluster)"
                    )

                if not core_is_fleet and not task_is_fleet:
                    task_count = int((task_nodes or {}).get("instance_count", 0) or 0)
                    if task_count > 0:
                        core_count = int((core_nodes or {}).get("instance_count", 1))
                        if core_count < 1:
                            raise AssertionError(
                                "m=_check_emr_cluster_configuration, "
                                "msg='core_nodes.instance_count' must be >= 1 when "
                                "task_nodes.instance_count > 0"
                            )
                else:
                    task_target = int(task_nodes.get("target_on_demand", 0) or 0) + int(
                        task_nodes.get("target_spot", 0) or 0
                    )
                    if task_target > 0:
                        core_target = int(
                            (core_nodes or {}).get("target_on_demand", 0) or 0
                        ) + int((core_nodes or {}).get("target_spot", 0) or 0)
                        if core_target < 1:
                            raise AssertionError(
                                "m=_check_emr_cluster_configuration, "
                                "msg='core_nodes' target_on_demand+target_spot "
                                "must be >= 1 when 'task_nodes' has TASK capacity "
                                "> 0"
                            )

            is_fleet_mode = core_is_fleet or task_is_fleet
            if is_fleet_mode:
                legacy_keys_present = _LEGACY_GROUP_ONLY_KEYS.intersection(
                    custom.keys()
                )
                if legacy_keys_present:
                    raise AssertionError(
                        "m=_check_emr_cluster_configuration, "
                        f"msg=Legacy instance-group keys "
                        f"{sorted(legacy_keys_present)} cannot be combined with "
                        "instance-fleet core_nodes/task_nodes"
                    )

            if task_availability is not None:
                if task_is_fleet:
                    raise AssertionError(
                        "m=_check_emr_cluster_configuration, "
                        "msg='aws_attributes.task_availability' is not applicable "
                        "when 'task_nodes' uses instance fleets; use "
                        "task_nodes.target_on_demand/target_spot instead"
                    )
                self._assert_task_availability(task_availability)
            return

        num_task_workers = custom.get("num_task_workers")
        if num_task_workers is not None:
            if not isinstance(num_task_workers, int) or isinstance(
                num_task_workers, bool
            ):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    "msg='num_task_workers' must be an integer"
                )
            if num_task_workers < 0:
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    "msg='num_task_workers' must be >= 0"
                )

        task_node_type_id = custom.get("task_node_type_id")
        if task_node_type_id is not None:
            if not isinstance(task_node_type_id, str) or not task_node_type_id.strip():
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    "msg='task_node_type_id' must be a non-empty string"
                )

        if task_availability is not None:
            self._assert_task_availability(task_availability)

        if num_task_workers is None or num_task_workers == 0:
            return

        num_workers = custom.get("num_workers")
        if num_workers is not None:
            if not isinstance(num_workers, int) or isinstance(num_workers, bool):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    "msg='num_workers' must be an integer when validating task split"
                )
            if num_task_workers >= num_workers:
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='num_task_workers' ({num_task_workers}) must be less than "
                    f"'num_workers' ({num_workers}) so at least 1 CORE node remains "
                    f"({num_workers - num_task_workers} CORE + {num_task_workers} TASK)"
                )

    @staticmethod
    def _assert_task_availability(task_availability: str) -> None:
        if (
            not isinstance(task_availability, str)
            or task_availability not in _EMR_TASK_AVAILABILITY_VALUES
        ):
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                "msg='aws_attributes.task_availability' must be SPOT or ON_DEMAND"
            )

    @staticmethod
    def _is_emr_fleet_block(block) -> bool:
        return isinstance(block, dict) and "instance_types" in block

    @classmethod
    def _assert_emr_node_group(cls, block: dict, name: str, *, min_count: int) -> None:
        if block is None:
            return
        if not isinstance(block, dict):
            raise AssertionError(
                f"m=_check_emr_cluster_configuration, msg='{name}' must be a dict"
            )

        present_group_keys = _GROUP_ONLY_NODE_BLOCK_KEYS.intersection(block.keys())
        present_fleet_keys = _FLEET_ONLY_NODE_BLOCK_KEYS.intersection(block.keys())
        if present_group_keys and present_fleet_keys:
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                f"msg='{name}' mixes instance-group keys "
                f"{sorted(present_group_keys)} with instance-fleet keys "
                f"{sorted(present_fleet_keys)}; use one style or the other, not both"
            )

        if block.get("max_nodes") is not None:
            cls._assert_emr_fleet_max_nodes(block, name)

        if cls._is_emr_fleet_block(block):
            cls._assert_emr_fleet_block(block, name)
        elif present_fleet_keys:
            cls._assert_emr_partial_fleet_override(block, name)
        else:
            cls._assert_emr_group_block(block, name, min_count=min_count)

    @staticmethod
    def _assert_emr_group_block(block: dict, name: str, *, min_count: int) -> None:
        instance_count = block.get("instance_count")
        if instance_count is not None:
            if not isinstance(instance_count, int) or isinstance(instance_count, bool):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.instance_count' must be an integer"
                )
            if instance_count < min_count:
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.instance_count' must be >= {min_count}"
                )
        node_type_id = block.get("node_type_id")
        if node_type_id is not None:
            if not isinstance(node_type_id, str) or not node_type_id.strip():
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.node_type_id' must be a non-empty string"
                )

    @staticmethod
    def _assert_emr_fleet_max_nodes(block: dict, name: str) -> None:
        max_nodes = block.get("max_nodes")
        if max_nodes is None:
            return
        if (
            not isinstance(max_nodes, int)
            or isinstance(max_nodes, bool)
            or max_nodes < 1
        ):
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                f"msg='{name}.max_nodes' must be an integer >= 1"
            )
        target_on_demand = int(block.get("target_on_demand", 0) or 0)
        target_spot = int(block.get("target_spot", 0) or 0)
        initial = target_on_demand + target_spot
        if initial > 0 and max_nodes < initial:
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                f"msg='{name}.max_nodes' ({max_nodes}) must be >= "
                f"target_on_demand+target_spot ({initial})"
            )

    @classmethod
    def _assert_emr_partial_fleet_override(cls, block: dict, name: str) -> None:
        """Fleet keys in a declaration override without instance_types (merged at runtime)."""
        cls._assert_emr_fleet_target_fields(block, name)
        allocation_strategy = block.get("allocation_strategy")
        if allocation_strategy is not None and (
            not isinstance(allocation_strategy, str)
            or allocation_strategy not in _EMR_FLEET_ALLOCATION_STRATEGIES
        ):
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                f"msg='{name}.allocation_strategy' must be one of "
                f"{sorted(_EMR_FLEET_ALLOCATION_STRATEGIES)}"
            )
        bid_price_percentage = block.get("bid_price_percentage")
        if bid_price_percentage is not None:
            if (
                not isinstance(bid_price_percentage, (int, float))
                or isinstance(bid_price_percentage, bool)
                or bid_price_percentage <= 0
            ):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.bid_price_percentage' must be a positive number"
                )
        spot_timeout_minutes = block.get("spot_timeout_minutes")
        if spot_timeout_minutes is not None:
            if (
                not isinstance(spot_timeout_minutes, int)
                or isinstance(spot_timeout_minutes, bool)
                or not (5 <= spot_timeout_minutes <= 1440)
            ):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.spot_timeout_minutes' must be an integer between "
                    "5 and 1440"
                )

    @staticmethod
    def _assert_emr_fleet_target_fields(
        block: dict, name: str, *, validate_defaults: bool = False
    ) -> None:
        max_nodes = block.get("max_nodes")
        for field_name in ("target_on_demand", "target_spot"):
            if field_name not in block and not validate_defaults:
                continue
            value = block.get(field_name, 0)
            if not isinstance(value, int) or isinstance(value, bool) or value < 0:
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.{field_name}' must be a non-negative integer"
                )
        if validate_defaults or "target_on_demand" in block or "target_spot" in block:
            tod = int(block.get("target_on_demand", 0) or 0)
            tsp = int(block.get("target_spot", 0) or 0)
            if tod + tsp <= 0:
                if name == "core_nodes":
                    raise AssertionError(
                        "m=_check_emr_cluster_configuration, "
                        "msg='core_nodes' target_on_demand+target_spot must be >= 1; "
                        "max_nodes does not allow core to scale from zero"
                    )
                if max_nodes is None:
                    raise AssertionError(
                        "m=_check_emr_cluster_configuration, "
                        f"msg='{name}' must set target_on_demand and/or target_spot > 0"
                        + (
                            " or set max_nodes for scale-from-zero"
                            if not validate_defaults
                            else ""
                        )
                    )

    @staticmethod
    def _assert_emr_fleet_block(block: dict, name: str) -> None:
        instance_types = block.get("instance_types")
        if not isinstance(instance_types, list) or not instance_types:
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                f"msg='{name}.instance_types' must be a non-empty list"
            )
        if not all(isinstance(t, str) and t.strip() for t in instance_types):
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                f"msg='{name}.instance_types' entries must be non-empty strings"
            )

        DAGClusterValidator._assert_emr_fleet_target_fields(
            block, name, validate_defaults=True
        )

        allocation_strategy = block.get("allocation_strategy")
        if allocation_strategy is not None and (
            not isinstance(allocation_strategy, str)
            or allocation_strategy not in _EMR_FLEET_ALLOCATION_STRATEGIES
        ):
            raise AssertionError(
                "m=_check_emr_cluster_configuration, "
                f"msg='{name}.allocation_strategy' must be one of "
                f"{sorted(_EMR_FLEET_ALLOCATION_STRATEGIES)}"
            )

        bid_price_percentage = block.get("bid_price_percentage")
        if bid_price_percentage is not None:
            if (
                not isinstance(bid_price_percentage, (int, float))
                or isinstance(bid_price_percentage, bool)
                or bid_price_percentage <= 0
            ):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.bid_price_percentage' must be a positive number"
                )

        spot_timeout_minutes = block.get("spot_timeout_minutes")
        if spot_timeout_minutes is not None:
            if (
                not isinstance(spot_timeout_minutes, int)
                or isinstance(spot_timeout_minutes, bool)
                or not (5 <= spot_timeout_minutes <= 1440)
            ):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    f"msg='{name}.spot_timeout_minutes' must be an integer between "
                    "5 and 1440"
                )
