import json

from bietlejuice.base.udfs.udf_enum import UDFEnum
from cerberus import Validator
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum
from bietlejuice.base.airflow.short_circuit_function_enum import (
    ShortCircuitFunctionEnum,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.databricks import DatabricksGroupNameEnum, ClusterPermissionEnum
from bietlejuice.base.airflow.dag_builders.main_builder.workflows.workflow_enum import (
    WorkflowEnum,
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
                "source_schema": {"type": "string", "empty": False},
                "source_database": {"type": "string", "empty": False},
                "custom_schema": {"type": "string", "empty": False},
                "database_type": {"type": "string", "empty": False, "required": False},
                "default_extraction_type": {"type": "string", "empty": False},
                "default_raw_extraction_type": {"type": "string", "empty": False},
                "default_clean_extraction_type": {"type": "string", "empty": False},
                "default_partitions": {"type": "list"},
                "default_raw_partitions": {"type": "list"},
                "default_clean_partitions": {"type": "list"},
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
                    "type": "dict",
                    "empty": False,
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
        },
    }

    def __init__(self, *args, **kwargs) -> None:
        super(DAGDeclarationValidator, self).__init__(*args, **kwargs)

    def validate(self, dag_declaration: dict) -> None:
        super(DAGDeclarationValidator, self).validate(
            dag_declaration, schema=self.__VALIDATION_SCHEMA
        )
        if self.errors:
            raise AssertionError(
                "m=validate, msg=One or more validation rules had errors:\n",
                f"{json.dumps(self.errors, indent=2)}",
            )
