import json

from cerberus import Validator

from bietlejuice.base.airflow.cluster_config_resolver import is_airflow_emr_cluster
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)

_EMR_TASK_AVAILABILITY_VALUES = frozenset({"SPOT", "ON_DEMAND"})
_EMR_ONLY_CUSTOM_CONFIG_KEYS = frozenset(
    {"num_task_workers", "task_node_type_id", "task_availability"}
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
            if (
                not isinstance(task_availability, str)
                or task_availability not in _EMR_TASK_AVAILABILITY_VALUES
            ):
                raise AssertionError(
                    "m=_check_emr_cluster_configuration, "
                    "msg='aws_attributes.task_availability' must be SPOT or ON_DEMAND"
                )

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
