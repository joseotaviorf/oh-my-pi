import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args


@pytest.fixture
def validator():
    return DAGDeclarationValidator()


def _base_declaration(**validation_cluster_type):
    declaration = {
        "dag": {"name": "test_dag", "owner": "Data Engineering"},
        "workflow": {"type": "query_delta", "layer": "enrich"},
        "cluster": {
            "type": "databricks_16_4_med_general_fleet",
            "access_control_list": {
                "group_name": "admins",
                "permission_level": "CAN_MANAGE",
            },
        },
    }
    if validation_cluster_type:
        declaration["validation"] = {
            "cluster": {"type": validation_cluster_type["type"]},
        }
    return declaration


class TestClusterValidationConfig:
    def test_valid_consolidation_cluster(self, validator):
        declaration = _base_declaration(type="consolidation_s_general_cluster")
        validator.validate(declaration)

    def test_rejects_non_consolidation_validation_cluster(self, validator):
        declaration = _base_declaration(type="databricks_16_4_med_general_fleet")
        with pytest.raises(AssertionError, match="consolidation_"):
            validator.validate(declaration)

    def test_rejects_same_cluster_as_prod(self, validator):
        declaration = _base_declaration(type="databricks_16_4_med_general_fleet")
        declaration["cluster"]["type"] = "consolidation_s_general_cluster"
        declaration["validation"]["cluster"]["type"] = "consolidation_s_general_cluster"
        with pytest.raises(AssertionError, match="differ"):
            validator.validate(declaration)

    def test_rejects_load_spark_job_without_opt_in(self, validator):
        declaration = _base_declaration(type="consolidation_s_general_cluster")
        declaration["workflow"]["load_spark_job"] = "custom_job"
        with pytest.raises(AssertionError, match="allow_custom_spark_job"):
            validator.validate(declaration)

    def test_allows_load_spark_job_with_opt_in(self, validator):
        declaration = _base_declaration(type="consolidation_s_general_cluster")
        declaration["workflow"]["load_spark_job"] = "custom_job"
        declaration["validation"]["allow_custom_spark_job"] = True
        validator.validate(declaration)


class TestMergeValidationClusterArgs:
    def test_inherits_prod_access_control_list(self):
        prod = {
            "type": "databricks_16_4_med_general_fleet",
            "access_control_list": {
                "group_name": "admins",
                "permission_level": "CAN_MANAGE",
            },
            "custom_configurations": {"spark.executor.memory": "4g"},
        }
        validation = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {"spark.sql.shuffle.partitions": "200"},
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["type"] == "consolidation_s_general_cluster"
        assert merged["access_control_list"] == prod["access_control_list"]
        assert merged["custom_configurations"] == {
            "spark.executor.memory": "4g",
            "spark.sql.shuffle.partitions": "200",
        }
