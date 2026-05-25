import json

from cerberus import Validator

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.api_ingestion_enums import (
    AuthenticationStrategyEnum,
    PaginationStrategyEnum,
    RateLimitingStrategyEnum,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.short_circuit_function_enum import (
    ShortCircuitFunctionEnum,
)
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.airflow.cluster_config_resolver import is_airflow_emr_cluster
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.udfs.udf_enum import UDFEnum

_EMR_TASK_AVAILABILITY_VALUES = frozenset({"SPOT", "ON_DEMAND"})
_EMR_ONLY_CUSTOM_CONFIG_KEYS = frozenset(
    {"num_task_workers", "task_node_type_id", "task_availability"}
)


class DAGDeclarationValidator(Validator):
    """Runs the validations for the DAG declaration info."""

    __VALIDATION_SCHEMA = {
        "dag": {
            "type": "dict",
            "allow_unknown": True,
            "required": True,
            "empty": False,
            "schema": {
                "name": {"type": "string", "required": True, "empty": False},
                "owner": {
                    "type": "string",
                    "required": True,
                    "empty": False,
                    "allowed": DAGOwnerEnum.get_available_enum_values(),
                },
            },
        },
        "workflow": {
            "type": "dict",
            "allow_unknown": False,
            "required": True,
            "empty": False,
            "schema": {
                "type": {
                    "type": "string",
                    "required": True,
                    "empty": False,
                    "allowed": WorkflowEnum.get_available_enum_values(),
                },
                "layer": {
                    "type": "string",
                    "required": True,
                    "empty": False,
                    "allowed": LayerEnum.get_available_enum_values(),
                },
                "execution_timeout_hours": {"type": "float", "empty": False},
                "max_tables_per_optimize_tasks": {
                    "type": "integer",
                    "min": 1,
                    "required": False,
                },
                "optimize_parallelism": {
                    "type": "integer",
                    "min": 1,
                    "required": False,
                },
                "source_schema": {"type": "string", "empty": False},
                "source_database": {"type": "string", "empty": False},
                "has_soft_delete": {"type": "boolean", "empty": False},
                "custom_schema": {"type": "string", "empty": False},
                "database_type": {"type": "string", "empty": False, "required": False},
                "default_extraction_type": {"type": "string", "empty": False},
                "default_raw_extraction_type": {"type": "string", "empty": False},
                "default_clean_extraction_type": {"type": "string", "empty": False},
                "default_partitions": {"type": "list"},
                "default_raw_partitions": {"type": "list"},
                "default_clean_partitions": {"type": "list"},
                "default_table_privileges": {"type": "dict"},
                "default_raw_table_privileges": {"type": "dict"},
                "default_clean_table_privileges": {"type": "dict"},
                "extra_query_template_params": {"type": "dict", "empty": False},
                "tables_customization": {"type": "dict", "empty": False},
                "lineage_product_database_name": {"type": "string", "empty": False},
                "short_circuit_customization": {
                    "type": "dict",
                    "empty": False,
                    "schema": {
                        "function": {
                            "type": "string",
                            "empty": False,
                            "allowed": ShortCircuitFunctionEnum.get_available_enum_values(),
                        },
                        "execution_date": {"type": "string", "required": False},
                        "function_params": {"type": "dict", "required": False},
                    },
                },
                "inner_dependencies": {"type": "dict", "empty": False},
                "clean_inner_dependencies": {"type": "dict", "empty": False},
                "raw_inner_dependencies": {"type": "dict", "empty": False},
                "has_load_to_redshift_task": {"type": "boolean", "empty": False},
                "spark_session_configs": {
                    "type": "dict",
                    "empty": False,
                    "schema": {
                        "udfs": {
                            "type": "list",
                            "empty": False,
                            "allowed": UDFEnum.get_available_enum_values(),
                        }
                    },
                },
                "has_hive_sync": {"type": "boolean", "empty": False, "required": False},
                "credentials_scope": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "dbutils_secret_key": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "load_options": {"type": "dict", "empty": False, "required": False},
                "bucket_config_name": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "load_spark_job": {"type": "string", "empty": False, "required": False},
                "spark_job_prefix": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "spark_job_arguments": {
                    "type": "list",
                    "empty": False,
                    "required": False,
                },
                "incoming_bucket_config_name": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "mysql_version": {"type": "string", "empty": False, "required": False},
                "dbutils_secret_scope": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "api_base_url": {
                    "anyof": [
                        {"type": "string", "empty": False},
                        {"type": "dict", "empty": False},
                    ],
                    "required": False,
                },
                "http_user_agent": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "authentication": {
                    "type": "dict",
                    "empty": False,
                    "required": False,
                    "schema": {
                        "strategy": {
                            "type": "string",
                            "required": True,
                            "empty": False,
                            "allowed": AuthenticationStrategyEnum.get_available_enum_values(),
                        },
                        "secret_key": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "token_url": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "scopes": {"type": "list", "empty": False, "required": False},
                        "client_id_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "client_secret_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "expires_at_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "fallback_token_expiration_seconds": {
                            "type": "integer",
                            "empty": False,
                            "required": False,
                        },
                        "token_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "api_key_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "location": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                            "allowed": ["header", "query_param"],
                        },
                        "header_name": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "query_param_name": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "username_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "password_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "token_payload_extras": {
                            "type": "dict",
                            "required": False,
                        },
                        "expires_in_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                        "token_request_format": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                            "allowed": ["form_basic_auth", "json_body"],
                        },
                        "access_token_field": {
                            "type": "string",
                            "empty": False,
                            "required": False,
                        },
                    },
                },
                "api_policies": {
                    "type": "dict",
                    "empty": False,
                    "required": False,
                    "schema": {
                        "rate_limiting": {
                            "type": "dict",
                            "empty": False,
                            "required": False,
                            "schema": {
                                "strategy": {
                                    "type": "string",
                                    "required": True,
                                    "empty": False,
                                    "allowed": RateLimitingStrategyEnum.get_available_enum_values(),
                                },
                                "delay_seconds": {
                                    "type": "float",
                                    "empty": False,
                                    "required": False,
                                },
                                "initial_delay_seconds": {
                                    "type": "integer",
                                    "min": 0,
                                    "required": False,
                                },
                                "retry_after_header": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                            },
                        },
                        "pagination": {
                            "type": "dict",
                            "empty": False,
                            "required": False,
                            "schema": {
                                "strategy": {
                                    "type": "string",
                                    "required": True,
                                    "empty": False,
                                    "allowed": PaginationStrategyEnum.get_available_enum_values(),
                                },
                                "limit_param": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                                "page_size": {
                                    "type": "integer",
                                    "empty": False,
                                    "required": False,
                                },
                                "offset_param": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                                "cursor_param": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                                "cursor_response_path": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                                "context_param": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                                "context_response_path": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                                "page_size_param": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                                "results_response_path": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                },
                            },
                        },
                        "error_handling": {
                            "type": "dict",
                            "empty": False,
                            "required": False,
                            "schema": {
                                "non_fatal_status_codes": {
                                    "type": "list",
                                    "empty": False,
                                    "required": False,
                                },
                                "retry_policy": {
                                    "type": "dict",
                                    "empty": False,
                                    "required": False,
                                    "schema": {
                                        "retries": {
                                            "type": "integer",
                                            "required": False,
                                        },
                                        "delay": {"type": "integer", "required": False},
                                        "backoff_factor": {
                                            "type": "integer",
                                            "required": False,
                                        },
                                        "status_forcelist": {
                                            "type": "list",
                                            "required": False,
                                            "schema": {"type": "integer"},
                                        },
                                    },
                                },
                            },
                        },
                    },
                },
                "date_format_mask": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "date_format": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "date_filter_column": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "payload_column_name": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "alert_channel": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                },
                "qube_specs": {"type": "dict", "empty": False},
                "wonka_config": {
                    "type": "dict",
                    "empty": False,
                    "required": False,
                    "schema": {
                        "name": {"type": "string", "required": True, "empty": False},
                        "pipeline_runner": {
                            "type": "string",
                            "required": True,
                            "empty": False,
                        },
                    },
                },
                "datazord_config": {
                    "type": "dict",
                    "empty": False,
                    "required": False,
                    "schema": {
                        "entity": {"type": "string", "required": True, "empty": False},
                        "table": {"type": "string", "required": True, "empty": False},
                        "key_columns": {
                            "type": "list",
                            "required": True,
                            "empty": False,
                        },
                    },
                },
            },
        },
        "cluster": {
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
        },
    }

    def __init__(self, *args, **kwargs) -> None:
        super().__init__(*args, **kwargs)

    def validate(self, dag_declaration: dict) -> None:
        """
        Validates the DAG declaration YAML structure and enforces workflow-specific rules.

        This method first validates the YAML structure against the schema, then applies
        workflow-specific validation rules. For api_ingestion workflow, it ensures:
        - load_spark_job is automatically set to "load_api_ingestion_raw" if not provided
        - api_base_url is required and configured for at least one environment
        - authentication is required
        - Each table in tables_customization has endpoint_path defined

        Args:
            dag_declaration: The parsed DAG declaration dictionary

        Raises:
            AssertionError: If validation fails with detailed error messages
        """
        super().validate(dag_declaration, schema=self.__VALIDATION_SCHEMA)
        if self.errors:
            raise AssertionError(
                "m=validate, msg=One or more validation rules had errors:\n",
                f"{json.dumps(self.errors, indent=2)}",
            )

        workflow_type = dag_declaration.get("workflow", {}).get("type")
        if workflow_type == WorkflowEnum.API_INGESTION_WORKFLOW.value:
            self._validate_api_ingestion_workflow(dag_declaration)

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
            if not isinstance(num_task_workers, int) or isinstance(num_task_workers, bool):
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

    def _validate_api_ingestion_workflow(self, dag_declaration: dict) -> None:
        """
        Validates specific requirements for api_ingestion workflow.

        This method enforces that:
        1. load_spark_job is set to "load_api_ingestion_raw" (or defined explicitly)
        2. api_base_url is provided and contains at least one environment configuration
        3. authentication configuration is provided
        4. Each table in tables_customization has endpoint_path defined

        Args:
            dag_declaration: The parsed DAG declaration dictionary

        Raises:
            AssertionError: If api_ingestion-specific validation fails
        """
        workflow = dag_declaration.get("workflow", {})
        tables_customization = workflow.get("tables_customization", {})

        if not workflow.get("load_spark_job"):
            workflow["load_spark_job"] = "load_api_ingestion_raw"

        api_base_url = workflow.get("api_base_url")
        if not api_base_url:
            raise AssertionError(
                "m=_validate_api_ingestion_workflow, "
                "msg='api_base_url' is required for api_ingestion workflow"
            )

        if isinstance(api_base_url, dict) and len(api_base_url) == 0:
            raise AssertionError(
                "m=_validate_api_ingestion_workflow, "
                "msg='api_base_url' dictionary must have at least one environment "
                "(e.g., prod, forno)"
            )

        if not isinstance(api_base_url, (str, dict)):
            raise AssertionError(
                "m=_validate_api_ingestion_workflow, "
                "msg='api_base_url' must be either a string (for all environments) "
                "or a dictionary with environment keys (e.g., prod, forno)"
            )

        workflow_authentication = workflow.get("authentication")

        if not workflow_authentication:
            tables_without_auth = []
            for table_name, table_config in tables_customization.items():
                if not isinstance(table_config, dict):
                    continue
                table_authentication = table_config.get("authentication")
                if not table_authentication:
                    tables_without_auth.append(table_name)

            if tables_without_auth:
                raise AssertionError(
                    "m=_validate_api_ingestion_workflow, "
                    "msg='authentication' is required for api_ingestion workflow. "
                    "It must be defined at workflow level or for each table in tables_customization. "
                    f"Tables without authentication: {tables_without_auth}"
                )

        for table_name, table_config in tables_customization.items():
            if not isinstance(table_config, dict):
                continue

            endpoint_path = table_config.get("endpoint_path")
            if not endpoint_path:
                raise AssertionError(
                    f"m=_validate_api_ingestion_workflow, "
                    f"msg='endpoint_path' is required for table '{table_name}' "
                    f"in api_ingestion workflow"
                )

            id_expansion = table_config.get("id_expansion")
            if id_expansion is not None:
                if not isinstance(id_expansion, dict):
                    raise AssertionError(
                        f"m=_validate_api_ingestion_workflow, "
                        f"msg='id_expansion' for table '{table_name}' must be a dict"
                    )
                if not id_expansion.get("source_table"):
                    raise AssertionError(
                        f"m=_validate_api_ingestion_workflow, "
                        f"msg='id_expansion.source_table' is required for table '{table_name}'"
                    )
                if not id_expansion.get("id_field"):
                    raise AssertionError(
                        f"m=_validate_api_ingestion_workflow, "
                        f"msg='id_expansion.id_field' is required for table '{table_name}'"
                    )
                has_param = bool(id_expansion.get("param_name"))
                has_path = bool(id_expansion.get("path_param"))
                has_json_body = bool(id_expansion.get("json_body_field"))
                mode_count = sum((has_param, has_path, has_json_body))
                if mode_count != 1:
                    raise AssertionError(
                        f"m=_validate_api_ingestion_workflow, "
                        f"msg='id_expansion' requires exactly one of 'param_name', "
                        f"'path_param', or 'json_body_field' for table '{table_name}'"
                    )
                correlation_field = id_expansion.get("correlation_field")
                if correlation_field is not None and (
                    not isinstance(correlation_field, str)
                    or not correlation_field.strip()
                ):
                    raise AssertionError(
                        f"m=_validate_api_ingestion_workflow, "
                        f"msg='id_expansion.correlation_field' for table '{table_name}' "
                        f"must be a non-empty string when set"
                    )
