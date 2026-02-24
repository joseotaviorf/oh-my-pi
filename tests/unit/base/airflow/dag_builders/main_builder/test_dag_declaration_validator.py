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
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": {
                            "group_name": "admins",
                            "permission_level": "CAN_MANAGE",
                        },
                    },
                },
                does_not_raise(),
            ),
            (
                {
                    "workflow": {"type": "", "layer": ""},
                    "dag": {"name": "", "owner": ""},
                    "cluster": {
                        "type": "",
                        "access_control_list": {
                            "group_name": "",
                            "permission_level": "",
                        },
                    },
                },
                pytest.raises(AssertionError),
            ),
            (
                {
                    "workflow": {},
                    "dag": {"name": "any_dag_name", "owner": "Data Engineering"},
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": {
                            "group_name": "admins",
                            "permission_level": "CAN_MANAGE",
                        },
                    },
                },
                pytest.raises(AssertionError),
            ),
            (
                {
                    "workflow": {"type": "query", "layer": "dw"},
                    "dag": {},
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": {
                            "group_name": "admins",
                            "permission_level": "CAN_MANAGE",
                        },
                    },
                },
                pytest.raises(AssertionError),
            ),
            (
                {
                    "workflow": {"type": "query", "layer": "dw"},
                    "dag": {"name": "any_dag_name", "owner": "Data Engineering"},
                    "cluster": {},
                },
                pytest.raises(AssertionError),
            ),
            ({"workflow": {}, "dag": {}, "cluster": {}}, pytest.raises(AssertionError)),
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
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
            "cluster": {
                "type": "test_cluster",
                "access_control_list": {
                    "group_name": "admins",
                    "permission_level": "CAN_MANAGE",
                },
            },
        }

        with pytest.raises(AssertionError):
            dag_declaration_validator.validate(dag_declaration=dag_declaration)
