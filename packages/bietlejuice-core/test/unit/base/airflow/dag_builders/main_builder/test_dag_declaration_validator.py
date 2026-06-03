from contextlib import nullcontext as does_not_raise

import pytest


class TestDAGDeclarationValidator:
    @pytest.mark.parametrize(
        "dag_declaration, expectation",
        [
            (
                {
                    "workflow": {"type": "query", "layer": "dw"},
                    "dag": {"name": "any_dag_name", "owner": "Data Engineering"},
                },
                does_not_raise(),
            ),
            (
                {
                    "workflow": {"type": "", "layer": ""},
                    "dag": {"name": "", "owner": ""},
                },
                pytest.raises(AssertionError),
            ),
            (
                {
                    "workflow": {},
                    "dag": {"name": "any_dag_name", "owner": "Data Engineering"},
                },
                pytest.raises(AssertionError),
            ),
            (
                {
                    "workflow": {"type": "query", "layer": "dw"},
                    "dag": {},
                },
                pytest.raises(AssertionError),
            ),
            ({"workflow": {}, "dag": {}}, pytest.raises(AssertionError)),
        ],
    )
    def test_validate(self, dag_declaration_validator, dag_declaration, expectation):
        with expectation:
            assert (
                dag_declaration_validator.validate(dag_declaration=dag_declaration)
                is None
            )


class TestDAGDeclarationValidatorAPIIngestionWorkflow:
    """Test suite for api_ingestion workflow-specific validation."""

    @pytest.fixture
    def dag_declaration_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
            DAGDeclarationValidator,
        )

        return DAGDeclarationValidator()

    def test_validate_api_ingestion_workflow_valid_config(
        self, dag_declaration_validator
    ):
        """Test that valid api_ingestion workflow config passes validation."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        dag_declaration_validator.validate(dag_declaration=dag_declaration)

        assert dag_declaration["workflow"]["load_spark_job"] == "load_api_ingestion_raw"

    def test_validate_api_ingestion_workflow_api_key_authentication(
        self, dag_declaration_validator
    ):
        """Test that api_key auth strategy is accepted in api_ingestion workflow."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "authentication": {
                    "strategy": "api_key",
                    "secret_key": "TEST_SECRET",
                    "header_name": "x-api-key",
                },
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_missing_api_base_url(
        self, dag_declaration_validator
    ):
        """Test that missing api_base_url raises AssertionError."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        with pytest.raises(
            AssertionError,
            match="'api_base_url' is required for api_ingestion workflow",
        ):
            dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_empty_api_base_url_dict(
        self, dag_declaration_validator
    ):
        """Test that empty api_base_url dict raises AssertionError."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": {},
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        with pytest.raises(AssertionError):
            dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_invalid_api_base_url_type(
        self, dag_declaration_validator
    ):
        """Test that invalid api_base_url type raises AssertionError."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": 123,
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        with pytest.raises(AssertionError):
            dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_missing_authentication(
        self, dag_declaration_validator
    ):
        """Test that missing authentication raises AssertionError."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        with pytest.raises(
            AssertionError,
            match="'authentication' is required for api_ingestion workflow",
        ):
            dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_missing_endpoint_path(
        self, dag_declaration_validator
    ):
        """Test that missing endpoint_path in table config raises AssertionError."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {}},
            },
        }

        with pytest.raises(
            AssertionError, match="'endpoint_path' is required for table 'events'"
        ):
            dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_explicit_load_spark_job(
        self, dag_declaration_validator
    ):
        """Test that explicit load_spark_job is preserved."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "load_spark_job": "custom_spark_job",
                "api_base_url": "https://api.example.com/",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        dag_declaration_validator.validate(dag_declaration=dag_declaration)

        assert dag_declaration["workflow"]["load_spark_job"] == "custom_spark_job"

    def test_validate_api_ingestion_workflow_multiple_tables(
        self, dag_declaration_validator
    ):
        """Test that validation works with multiple tables."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {
                    "events": {"endpoint_path": "events"},
                    "users": {"endpoint_path": "users"},
                    "sessions": {"endpoint_path": "sessions"},
                },
            },
        }

        dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_dict_api_base_url(
        self, dag_declaration_validator
    ):
        """Test that dict api_base_url is validated correctly."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": {
                    "forno": "https://api-forno.example.com/",
                    "prod": "https://api-prod.example.com/",
                },
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        dag_declaration_validator.validate(dag_declaration=dag_declaration)

    def test_validate_api_ingestion_workflow_with_payload_column_name(
        self, dag_declaration_validator
    ):
        """Test that payload_column_name in workflow config passes validation."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "payload_column_name": "raw_payload",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        dag_declaration_validator.validate(dag_declaration=dag_declaration)

        assert dag_declaration["workflow"]["payload_column_name"] == "raw_payload"

    def test_validate_api_ingestion_workflow_without_payload_column_name(
        self, dag_declaration_validator
    ):
        """Test that missing payload_column_name is valid (defaults to 'payload')."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        dag_declaration_validator.validate(dag_declaration=dag_declaration)

        # payload_column_name is optional, should not be in workflow
        assert "payload_column_name" not in dag_declaration["workflow"]

    def test_validate_api_ingestion_workflow_empty_payload_column_name(
        self, dag_declaration_validator
    ):
        """Test that empty payload_column_name raises validation error."""
        dag_declaration = {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "payload_column_name": "",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"events": {"endpoint_path": "events"}},
            },
        }

        with pytest.raises(AssertionError):
            dag_declaration_validator.validate(dag_declaration=dag_declaration)


class TestDAGDeclarationValidatorIdExpansion:
    """Test suite for id_expansion validation in api_ingestion workflow."""

    @pytest.fixture
    def dag_declaration_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
            DAGDeclarationValidator,
        )

        return DAGDeclarationValidator()

    def _base_declaration(self, table_config):
        return {
            "dag": {"name": "test_api_dag", "owner": "Data Engineering"},
            "workflow": {
                "type": "api_ingestion",
                "layer": "raw",
                "api_base_url": "https://api.example.com/",
                "authentication": {"strategy": "oauth2_client_credentials"},
                "tables_customization": {"hoursbank_totals": table_config},
            },
        }

    def test_valid_id_expansion_with_param_name_passes(self, dag_declaration_validator):
        """Valid id_expansion using param_name (query param) passes validation."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "employees/hoursbank/totals",
                "id_expansion": {
                    "source_table": "employees",
                    "id_field": "uuid",
                    "param_name": "employeeUuid",
                },
            }
        )

        dag_declaration_validator.validate(dag_declaration=declaration)

    def test_valid_id_expansion_with_path_param_passes(self, dag_declaration_validator):
        """Valid id_expansion using path_param (URL injection) passes validation."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "holidays-groups/holidays/employees/{employeeUuid}",
                "id_expansion": {
                    "source_table": "employees",
                    "id_field": "uuid",
                    "path_param": "employeeUuid",
                },
            }
        )

        dag_declaration_validator.validate(dag_declaration=declaration)

    def test_missing_source_table_raises(self, dag_declaration_validator):
        """Missing id_expansion.source_table raises AssertionError."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "employees/hoursbank/totals",
                "id_expansion": {
                    "id_field": "uuid",
                    "param_name": "employeeUuid",
                },
            }
        )

        with pytest.raises(AssertionError, match="id_expansion.source_table"):
            dag_declaration_validator.validate(dag_declaration=declaration)

    def test_missing_id_field_raises(self, dag_declaration_validator):
        """Missing id_expansion.id_field raises AssertionError."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "employees/hoursbank/totals",
                "id_expansion": {
                    "source_table": "employees",
                    "param_name": "employeeUuid",
                },
            }
        )

        with pytest.raises(AssertionError, match="id_expansion.id_field"):
            dag_declaration_validator.validate(dag_declaration=declaration)

    def test_missing_param_name_and_path_param_raises(self, dag_declaration_validator):
        """Missing both param_name and path_param raises AssertionError."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "employees/hoursbank/totals",
                "id_expansion": {
                    "source_table": "employees",
                    "id_field": "uuid",
                },
            }
        )

        with pytest.raises(AssertionError, match="exactly one of"):
            dag_declaration_validator.validate(dag_declaration=declaration)

    def test_valid_id_expansion_with_json_body_field_passes(
        self, dag_declaration_validator
    ):
        """Valid id_expansion using json_body_field (POST body) passes validation."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "costs/list",
                "params": {},
                "id_expansion": {
                    "source_table": "employees",
                    "id_field": "externalId",
                    "correlation_field": "employeeExternalId",
                    "json_body_field": "employeeExternalId",
                },
            }
        )

        dag_declaration_validator.validate(dag_declaration=declaration)

    def test_id_expansion_multiple_target_modes_raises(self, dag_declaration_validator):
        """Setting more than one of param_name, path_param, json_body_field raises."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "costs/list",
                "id_expansion": {
                    "source_table": "employees",
                    "id_field": "externalId",
                    "param_name": "x",
                    "json_body_field": "employeeExternalId",
                },
            }
        )

        with pytest.raises(AssertionError, match="exactly one of"):
            dag_declaration_validator.validate(dag_declaration=declaration)

    def test_id_expansion_not_a_dict_raises(self, dag_declaration_validator):
        """Non-dict id_expansion raises AssertionError."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "employees/hoursbank/totals",
                "id_expansion": "employees.uuid",
            }
        )

        with pytest.raises(AssertionError, match="must be a dict"):
            dag_declaration_validator.validate(dag_declaration=declaration)

    def test_table_without_id_expansion_still_valid(self, dag_declaration_validator):
        """Tables without id_expansion are not affected by the new validation."""
        declaration = self._base_declaration(
            {
                "endpoint_path": "employees",
                "params": {},
            }
        )

        dag_declaration_validator.validate(dag_declaration=declaration)


class TestDAGDeclarationValidatorQueryViewWorkflow:
    @pytest.fixture
    def dag_declaration_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
            DAGDeclarationValidator,
        )

        return DAGDeclarationValidator()

    @pytest.fixture
    def base_declaration(self):
        return {
            "dag": {"name": "test_query_view", "owner": "Data Engineering"},
            "workflow": {
                "type": "query_view",
                "layer": "enrich",
            },
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
            },
        }

    @pytest.mark.parametrize(
        "workflow_config",
        [
            {"sync": ["databricks"], "sql_dialect": "databricks"},
            {"sync": ["databricks", "trino"], "sql_dialect": "databricks"},
            {"sync": ["trino"], "sql_dialect": "trino"},
            {
                "sync": ["databricks"],
                "sql_dialect": "databricks",
                "tables_customization": {
                    "table_a": {"sync": ["trino"], "sql_dialect": "trino"}
                },
            },
        ],
    )
    def test_validate_query_view_sync_config(
        self, dag_declaration_validator, base_declaration, workflow_config
    ):
        # arrange
        base_declaration["workflow"].update(workflow_config)

        # act & assert
        dag_declaration_validator.validate(dag_declaration=base_declaration)

    @pytest.mark.parametrize(
        "workflow_config, error_match",
        [
            ({"sync": []}, "sync"),
            ({"sync": ["athena"], "sql_dialect": "databricks"}, "sync"),
            ({"sync": ["databricks"], "sql_dialect": "spark"}, "sql_dialect"),
            (
                {"has_hive_sync": True},
                "Invalid query_view sync configuration",
            ),
            (
                {
                    "sync": ["databricks"],
                    "sql_dialect": "databricks",
                    "tables_customization": {"table_a": {"sync": ["athena"]}},
                },
                "table 'table_a'",
            ),
        ],
    )
    def test_validate_query_view_rejects_invalid_sync_config(
        self,
        dag_declaration_validator,
        base_declaration,
        workflow_config,
        error_match,
    ):
        # arrange
        base_declaration["workflow"].update(workflow_config)

        # act & assert
        with pytest.raises(AssertionError, match=error_match):
            dag_declaration_validator.validate(dag_declaration=base_declaration)
