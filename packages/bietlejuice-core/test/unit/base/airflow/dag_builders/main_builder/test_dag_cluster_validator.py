from contextlib import nullcontext as does_not_raise

import pytest


class TestDAGClusterValidator:
    @pytest.fixture
    def dag_cluster_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_cluster_validator import (
            DAGClusterValidator,
        )

        return DAGClusterValidator()

    @pytest.mark.parametrize(
        "dag_declaration, expectation",
        [
            (
                {
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
                    "cluster": {
                        "type": "any_cluster_type",
                        "access_control_list": [
                            {
                                "group_name": "admins",
                                "permission_level": "CAN_MANAGE",
                            },
                            {
                                "group_name": "analytics-engineers",
                                "permission_level": "CAN_ATTACH_TO",
                            },
                        ],
                    },
                },
                does_not_raise(),
            ),
            (
                {
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
                {"cluster": {}},
                pytest.raises(AssertionError),
            ),
            ({}, pytest.raises(AssertionError)),
        ],
    )
    def test_validate_cluster(
        self, dag_cluster_validator, dag_declaration, expectation
    ):
        with expectation:
            assert (
                dag_cluster_validator.validate_cluster(dag_declaration=dag_declaration)
                is None
            )


class TestEmrClusterConfiguration:
    @pytest.fixture
    def dag_cluster_validator(self):
        from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_cluster_validator import (
            DAGClusterValidator,
        )

        return DAGClusterValidator()

    def _base_declaration(self, cluster):
        return {"cluster": cluster}

    def test_emr_cluster_valid_task_split_passes(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "num_workers": 5,
                    "num_task_workers": 3,
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_custom_spark_version_valid_split_passes(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "custom_cluster",
                "custom_configurations": {
                    "spark_version": "emr-7.12.0",
                    "num_workers": 4,
                    "num_task_workers": 2,
                    "aws_attributes": {"task_availability": "ON_DEMAND"},
                },
            }
        )
        dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_num_task_workers_equals_num_workers_raises(
        self, dag_cluster_validator
    ):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "num_workers": 3,
                    "num_task_workers": 3,
                },
            }
        )
        with pytest.raises(AssertionError, match="must be less than"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_databricks_cluster_num_task_workers_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "databricks_16_4_med_general_cluster",
                "custom_configurations": {"num_task_workers": 1},
            }
        )
        with pytest.raises(AssertionError, match="EMR-only cluster keys"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_databricks_cluster_task_availability_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "databricks_16_4_med_general_cluster",
                "custom_configurations": {
                    "aws_attributes": {"task_availability": "SPOT"},
                },
            }
        )
        with pytest.raises(AssertionError, match="EMR-only cluster keys"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)

    def test_emr_cluster_invalid_task_availability_raises(self, dag_cluster_validator):
        declaration = self._base_declaration(
            {
                "type": "emr_7_12_med_general_cluster",
                "custom_configurations": {
                    "num_workers": 3,
                    "num_task_workers": 1,
                    "aws_attributes": {"task_availability": "SPOT_WITH_FALLBACK"},
                },
            }
        )
        with pytest.raises(AssertionError, match="task_availability"):
            dag_cluster_validator.validate_cluster(dag_declaration=declaration)
