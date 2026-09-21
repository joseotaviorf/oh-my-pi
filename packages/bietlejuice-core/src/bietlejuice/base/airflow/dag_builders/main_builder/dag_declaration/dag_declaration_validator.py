import json

from cerberus import Validator

from bietlejuice.base.airflow.cluster_config_resolver import (
    CLUSTER_VALIDATION_EXCLUDED_DAGS,
    validation_resolves_to_prod_spec,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.api_ingestion_enums import (
    AuthenticationStrategyEnum,
    PaginationStrategyEnum,
    RateLimitingStrategyEnum,
)
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
)
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.enums.criticality_enum import (
    SLA_DEADLINE_PATTERN,
    CriticalityEnum,
)
from bietlejuice.base.airflow.short_circuit_function_enum import (
    ShortCircuitFunctionEnum,
)
from bietlejuice.base.databricks.cluster_permission_enum import ClusterPermissionEnum
from bietlejuice.base.databricks.databricks_group_name_enum import (
    DatabricksGroupNameEnum,
)
from bietlejuice.base.db.datalake_metastore_mapping import TRANSFORMATION_GRADES
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.query_view_sync import (
    QueryViewSqlDialectEnum,
    QueryViewSyncTargetEnum,
    normalize_query_view_sync_config,
)
from bietlejuice.base.udfs.udf_enum import UDFEnum
from bietlejuice.base.validation.cluster_args import (
    CONSOLIDATION_PRESET_TYPE_PREFIXES,
)
from bietlejuice.services.configuration_service import ConfigurationService


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
                "max_active_tasks": {"type": "integer", "min": 1, "required": False},
                "criticality": {
                    "type": "string",
                    "required": False,
                    "allowed": CriticalityEnum.get_available_enum_values(),
                },
                "sla_deadline_localtime": {
                    "type": "string",
                    "required": False,
                    "regex": SLA_DEADLINE_PATTERN,
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
                "max_tables_per_cluster": {
                    "type": "integer",
                    "min": 1,
                    "required": False,
                },
                "optimize_parallelism": {
                    "type": "integer",
                    "min": 1,
                    "required": False,
                },
                "incremental_optimize": {
                    "type": "boolean",
                    "empty": False,
                    "required": False,
                },
                "incremental_partition_sync": {
                    "type": "boolean",
                    "empty": False,
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
                "tables_customization": {
                    "type": "dict",
                    "empty": False,
                    "valuesrules": {
                        "type": "dict",
                        "allow_unknown": True,
                        "schema": {
                            "criticality": {
                                "type": "string",
                                "required": False,
                                "allowed": CriticalityEnum.get_available_enum_values(),
                            },
                        },
                    },
                },
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
                # Required only when layer is transformation; rejected on other layers
                # in ``_check_transformation_grade``.
                "transformation_grade": {
                    "type": "string",
                    "required": False,
                    "empty": False,
                    "allowed": ["clean", "curated"],
                },
                "observability": {
                    "type": "dict",
                    "empty": False,
                    "required": False,
                    "schema": {
                        "enabled": {
                            "type": "boolean",
                            "empty": False,
                            "required": False,
                        },
                        "column_checks": {
                            "type": "boolean",
                            "empty": False,
                            "required": False,
                        },
                        "tables": {
                            "type": "list",
                            "empty": False,
                            "required": False,
                            "schema": {"type": "string", "empty": False},
                        },
                    },
                },
                "serialize_dq_after_default_row": {
                    "type": "boolean",
                    "empty": False,
                    "required": False,
                },
                "sync": {
                    "type": "list",
                    "empty": False,
                    "required": False,
                    "schema": {
                        "type": "string",
                        "allowed": QueryViewSyncTargetEnum.get_available_enum_values(),
                    },
                },
                "sql_dialect": {
                    "type": "string",
                    "empty": False,
                    "required": False,
                    "allowed": QueryViewSqlDialectEnum.get_available_enum_values(),
                },
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
                "http_headers": {
                    "type": "dict",
                    "empty": False,
                    "required": False,
                    "keysrules": {"type": "string", "empty": False},
                    "valuesrules": {"type": "string", "empty": False},
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
                                "cursor_location": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                    "allowed": ["header", "param"],
                                },
                                "context_location": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                    "allowed": ["header", "param"],
                                },
                                "page_size_location": {
                                    "type": "string",
                                    "empty": False,
                                    "required": False,
                                    "allowed": ["header", "param"],
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
                "gchat_export_summary": {
                    "type": "boolean",
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
                            "required": False,
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
                        "kafka_topic": {
                            "type": "string",
                            "required": False,
                            "empty": False,
                        },
                        "topic_namespace": {
                            "type": "string",
                            "required": False,
                            "empty": False,
                        },
                        "schema_validation": {
                            "type": "string",
                            "required": False,
                            "empty": False,
                            "allowed": ["cassandra", "none"],
                        },
                        "include_delete_events": {
                            "type": "boolean",
                            "required": False,
                        },
                    },
                },
            },
        },
        "validation": {
            "type": "dict",
            "required": False,
            "empty": False,
            "schema": {
                "cluster": {
                    "type": "dict",
                    "required": True,
                    "empty": False,
                    "schema": {
                        "type": {"type": "string", "required": True, "empty": False},
                        "custom_configurations": {
                            "type": "dict",
                            "required": False,
                            "empty": False,
                        },
                        "custom_libraries": {
                            "type": "list",
                            "required": False,
                            "empty": False,
                        },
                        "databricks_conn_id": {"type": "string", "empty": False},
                        "access_control_list": {
                            "empty": False,
                            "required": False,
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
                    },
                },
                "allow_custom_spark_job": {
                    "type": "boolean",
                    "required": False,
                    "empty": False,
                },
            },
        },
        # Defensive: validate() is called on raw_declaration (cluster already popped),
        # but allows direct calls with a merged dict without Cerberus rejecting the key.
        "cluster": {
            "type": "dict",
            "required": False,
            "allow_unknown": True,
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

        self._check_transformation_grade(dag_declaration)
        self._check_cluster_validation_config(dag_declaration)
        if dag_declaration.get("cluster"):
            self.validate_cluster_validation_cluster_diff(
                dag_declaration=dag_declaration
            )

        workflow_type = dag_declaration.get("workflow", {}).get("type")
        if workflow_type == WorkflowEnum.API_INGESTION_WORKFLOW.value:
            self._validate_api_ingestion_workflow(dag_declaration)
        if workflow_type == WorkflowEnum.MILESTONE_DELTA_WORKFLOW.value:
            self._validate_milestone_delta_workflow(dag_declaration)
        if workflow_type == WorkflowEnum.QUERY_VIEW_WORKFLOW.value:
            self._validate_query_view_workflow(dag_declaration)
        if workflow_type == WorkflowEnum.QUERY_DELTA_DATAZORD_WORKFLOW.value:
            self._check_query_delta_datazord_config(dag_declaration)
        if workflow_type == WorkflowEnum.QUERY_DELTA_WORKFLOW.value:
            self._check_query_delta_rejects_datazord_config(dag_declaration)

    def _check_transformation_grade(self, dag_declaration: dict) -> None:
        workflow = dag_declaration.get("workflow") or {}
        layer = workflow.get("layer")
        grade = workflow.get("transformation_grade")
        if layer == LayerEnum.TRANSFORMATION.value:
            if grade not in TRANSFORMATION_GRADES:
                raise AssertionError(
                    "m=_check_transformation_grade, "
                    "msg=workflow.transformation_grade is required when layer is "
                    "transformation and must be 'clean' or 'curated'"
                )
            return
        if grade is not None:
            raise AssertionError(
                "m=_check_transformation_grade, "
                "msg=workflow.transformation_grade is only allowed when layer is "
                "transformation"
            )

    _PAGINATION_LOCATION_KEYS = (
        "cursor_location",
        "context_location",
        "page_size_location",
    )
    _ALLOWED_PAGINATION_LOCATIONS = ("header", "param")

    def _check_http_headers_map(self, http_headers, scope_label: str) -> None:
        if http_headers is None:
            return
        if not isinstance(http_headers, dict):
            raise AssertionError(
                "m=_validate_api_ingestion_workflow, "
                f"msg='http_headers' {scope_label} must be a mapping of "
                "header name to string value"
            )
        for header_name, header_value in http_headers.items():
            if not isinstance(header_name, str) or not header_name.strip():
                raise AssertionError(
                    "m=_validate_api_ingestion_workflow, "
                    f"msg='http_headers' {scope_label} keys must be non-empty strings"
                )
            if not isinstance(header_value, str) or not header_value.strip():
                raise AssertionError(
                    "m=_validate_api_ingestion_workflow, "
                    f"msg='http_headers' {scope_label} values must be non-empty strings"
                )

    def _check_pagination_locations(self, pagination_config, scope_label: str) -> None:
        if not isinstance(pagination_config, dict):
            return
        for location_key in self._PAGINATION_LOCATION_KEYS:
            location_value = pagination_config.get(location_key)
            if location_value is None:
                continue
            if location_value not in self._ALLOWED_PAGINATION_LOCATIONS:
                raise AssertionError(
                    "m=_validate_api_ingestion_workflow, "
                    f"msg='{location_key}' {scope_label} must be one of "
                    f"{list(self._ALLOWED_PAGINATION_LOCATIONS)}, got {location_value!r}"
                )

    def _validate_query_view_workflow(self, dag_declaration: dict) -> None:
        workflow = dag_declaration.get("workflow", {})
        if workflow.get("layer") == LayerEnum.TRANSFORMATION.value:
            raise AssertionError(
                "m=_validate_query_view_workflow, "
                "msg=workflow.type query_view is not supported when layer is "
                "transformation"
            )
        tables_customization = workflow.get("tables_customization", {})

        try:
            normalize_query_view_sync_config(workflow)
        except ValueError as exc:
            raise AssertionError(
                "m=_validate_query_view_workflow, "
                f"msg=Invalid query_view sync configuration: {exc}"
            ) from exc

        for table_name, table_config in tables_customization.items():
            if not isinstance(table_config, dict):
                continue

            try:
                normalize_query_view_sync_config(workflow, table_config)
            except ValueError as exc:
                raise AssertionError(
                    "m=_validate_query_view_workflow, "
                    f"msg=Invalid query_view sync configuration for table "
                    f"'{table_name}': {exc}"
                ) from exc

    @staticmethod
    def _check_query_delta_datazord_config(dag_declaration: dict) -> None:
        workflow = dag_declaration.get("workflow", {})
        datazord_config = workflow.get("datazord_config")
        if not datazord_config:
            raise AssertionError(
                "m=_check_query_delta_datazord_config, "
                "msg='datazord_config' is required when workflow.type is "
                "'query_delta_datazord'"
            )

    @staticmethod
    def _check_query_delta_rejects_datazord_config(dag_declaration: dict) -> None:
        workflow = dag_declaration.get("workflow", {})
        if workflow.get("datazord_config"):
            raise AssertionError(
                "m=_check_query_delta_rejects_datazord_config, "
                "msg='datazord_config' is only supported for workflow.type "
                "'query_delta_datazord' (or 'wonka'); use "
                "'query_delta_datazord' for CDF → Datazord streaming"
            )

    def validate_cluster_validation_cluster_diff(self, dag_declaration: dict) -> None:
        """Validate prod vs consolidation cluster types after cluster YAML is merged."""
        dag_name = (dag_declaration.get("dag") or {}).get("name")
        if dag_name in CLUSTER_VALIDATION_EXCLUDED_DAGS:
            return

        validation = dag_declaration.get("validation")
        if not validation:
            return

        validation_cluster_type = validation.get("cluster", {}).get("type")
        if not validation_cluster_type:
            return

        prod_cluster = dag_declaration.get("cluster", {})

        try:
            is_noop = validation_resolves_to_prod_spec(
                prod_cluster, validation.get("cluster", {}), ConfigurationService()
            )
        except (ValueError, IndexError):
            # ENVIRONMENT unset or unresolved preset type: other validators/build
            # steps surface those; don't turn this backstop into a new crash.
            is_noop = False
        if is_noop:
            raise AssertionError(
                "m=validate_cluster_validation_cluster_diff, "
                "msg='validation.cluster' resolves to the same effective cluster "
                "spec as prod 'cluster'; it would not validate any change"
            )

    def validate_py_files_matches_spark_jobs_structure(
        self, dag_declaration: dict
    ) -> None:
        """A table_customization ``py_files: true`` tells EMR spark-submit to
        use the structure-preserving ``pkg.zip`` that
        upload_dag_packages_artifact_into_s3.py only builds when spark_jobs/
        has subdirectories. If the flag is set but there is nothing to zip,
        the task 404s on a zip that will never exist. Catch that here, at
        declaration-validation time, instead of on a live EMR run."""
        from os import path, scandir

        from bietlejuice.base.service.dag_packages_path_service import (
            DAGPackagesPathService,
        )

        dag_name = (dag_declaration.get("dag") or {}).get("name")
        workflow = dag_declaration.get("workflow", {})
        tables_customization = workflow.get("tables_customization") or {}

        tables_with_py_files = [
            table_name
            for table_name, customization in tables_customization.items()
            if isinstance(customization, dict) and customization.get("py_files")
        ]
        if not tables_with_py_files:
            return

        dag_path = DAGPackagesPathService.get_dag_path(dag_name)
        if not dag_path:
            # Can't resolve the local path in this context (e.g. cwd isn't
            # rooted where DAGPackagesPathService expects) -- fail open rather
            # than block validation on a check we can't actually perform.
            return
        spark_jobs_dir = path.join(dag_path, "spark_jobs")
        has_nested_package = path.isdir(spark_jobs_dir) and any(
            entry.is_dir() for entry in scandir(spark_jobs_dir)
        )
        if not has_nested_package:
            raise AssertionError(
                "m=validate_py_files_matches_spark_jobs_structure, "
                f"msg=table(s) {tables_with_py_files} in dag '{dag_name}' set "
                f"py_files: true but {spark_jobs_dir} has no subdirectories to "
                "zip; remove the flag, or add the sibling modules it's meant to "
                "ship via EMR --py-files."
            )

    @staticmethod
    def _check_cluster_validation_config(dag_declaration: dict) -> None:
        dag_name = (dag_declaration.get("dag") or {}).get("name")
        if dag_name in CLUSTER_VALIDATION_EXCLUDED_DAGS:
            return

        validation = dag_declaration.get("validation")
        if not validation:
            return

        cluster = validation.get("cluster")
        if not cluster or not cluster.get("type"):
            raise AssertionError(
                "m=_check_cluster_validation_config, "
                "msg='validation.cluster.type' is required when 'validation' is set"
            )

        validation_cluster_type = cluster["type"]
        if not (
            validation_cluster_type.startswith(CONSOLIDATION_PRESET_TYPE_PREFIXES)
            or validation_cluster_type.startswith("emr_7_12_")
        ):
            raise AssertionError(
                "m=_check_cluster_validation_config, "
                "msg='validation.cluster.type' must start with 'consolidation_', "
                "'wonka_consolidation_', or 'emr_7_12_'"
            )

        workflow = dag_declaration.get("workflow", {})
        tables_customization = workflow.get("tables_customization")
        if not isinstance(tables_customization, dict):
            tables_customization = {}
        has_custom_spark_job = bool(workflow.get("load_spark_job")) or any(
            isinstance(cfg, dict) and cfg.get("load_spark_job")
            for cfg in tables_customization.values()
        )
        if has_custom_spark_job and not validation.get("allow_custom_spark_job"):
            raise AssertionError(
                "m=_check_cluster_validation_config, "
                "msg=DAGs with load_spark_job require validation.allow_custom_spark_job: true"
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

        self._check_http_headers_map(workflow.get("http_headers"), "at workflow level")
        workflow_pagination = workflow.get("pagination") or (
            workflow.get("api_policies") or {}
        ).get("pagination")
        self._check_pagination_locations(workflow_pagination, "at workflow level")

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

            self._check_http_headers_map(
                table_config.get("http_headers"),
                f"for table '{table_name}'",
            )
            table_pagination = table_config.get("pagination") or (
                table_config.get("api_policies") or {}
            ).get("pagination")
            self._check_pagination_locations(
                table_pagination, f"for table '{table_name}'"
            )

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

    def _validate_milestone_delta_workflow(self, dag_declaration: dict) -> None:
        """Defaults and checks for milestone_delta (one table ← many strategy SQLs)."""
        workflow = dag_declaration.get("workflow", {})
        tables_customization = workflow.get("tables_customization") or {}

        if not tables_customization:
            raise AssertionError(
                "m=_validate_milestone_delta_workflow, "
                "msg='tables_customization' is required for milestone_delta"
            )

        if not workflow.get("load_spark_job"):
            workflow["load_spark_job"] = "load_milestone_dimension"
        if not workflow.get("spark_job_prefix"):
            # CI uploads dags/cross/base/spark_jobs/ under prefix "base"
            workflow["spark_job_prefix"] = "base"

        layer = workflow.get("layer")
        if layer and layer != LayerEnum.DW.value:
            raise AssertionError(
                "m=_validate_milestone_delta_workflow, "
                "msg=milestone_delta v1 only supports workflow.layer: dw"
            )

        default_args = [
            "{environment}",
            "{bucket}",
            "{dag_name}",
            "{schema}",
            "{table_name}",
            "--layer",
            "dw",
            "--merge-on",
            "{merge_on}",
            "--milestones-to-run",
            "{{ (dag_run.conf.get('milestones_to_run') if dag_run.conf else none) | tojson }}",
            "--bootstrap-milestones",
            "{{ (dag_run.conf.get('bootstrap_milestones') if dag_run.conf else none) | tojson }}",
        ]
        if not workflow.get("spark_job_arguments"):
            workflow["spark_job_arguments"] = default_args

        for table_name, table_config in tables_customization.items():
            if not isinstance(table_config, dict):
                raise AssertionError(
                    "m=_validate_milestone_delta_workflow, "
                    f"msg=tables_customization.{table_name} must be a mapping"
                )
            merge_on = table_config.get("merge_on")
            if not merge_on or not isinstance(merge_on, list):
                raise AssertionError(
                    "m=_validate_milestone_delta_workflow, "
                    f"msg=tables_customization.{table_name}.merge_on must be a non-empty list"
                )
            if "milestone_type" not in merge_on:
                raise AssertionError(
                    "m=_validate_milestone_delta_workflow, "
                    f"msg=tables_customization.{table_name}.merge_on must include "
                    "'milestone_type'"
                )
            entity_keys = [c for c in merge_on if c != "milestone_type"]
            if not entity_keys:
                raise AssertionError(
                    "m=_validate_milestone_delta_workflow, "
                    f"msg=tables_customization.{table_name}.merge_on must include "
                    "at least one entity key besides milestone_type"
                )
