import os
from unittest import mock

import pytest

from bietlejuice.base.airflow.cluster_config_resolver import (
    merge_cluster_configuration,
    validation_resolves_to_prod_spec,
)
from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_declaration_validator import (
    DAGDeclarationValidator,
)
from bietlejuice.base.validation.cluster_args import merge_validation_cluster_args
from bietlejuice.services.configuration_service import ConfigurationService


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

    def test_valid_wonka_consolidation_cluster(self, validator):
        declaration = _base_declaration(type="wonka_consolidation_m_general_cluster")
        validator.validate(declaration)

    def test_valid_emr_validation_cluster_when_prod_is_databricks(self, validator):
        declaration = _base_declaration(type="emr_7_12_consolidation_xl_memory_cluster")
        declaration["cluster"]["type"] = "consolidation_xl_memory_cluster"
        declaration["cluster"]["databricks_conn_id"] = "databricks_new"
        declaration["cluster"]["custom_configurations"] = {"num_workers": 3}
        declaration["validation"]["cluster"]["custom_configurations"] = {
            "core_nodes": {"node_type_id": "r7g.8xlarge", "instance_count": 1},
            "task_nodes": {"node_type_id": "r7g.8xlarge", "instance_count": 2},
        }
        validator.validate(declaration)

    def test_rejects_non_consolidation_validation_cluster(self, validator):
        declaration = _base_declaration(type="databricks_16_4_med_general_fleet")
        with pytest.raises(AssertionError, match="consolidation_"):
            validator.validate(declaration)

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_rejects_same_cluster_as_prod_without_overrides(self, validator):
        ConfigurationService._instance_cache.clear()
        declaration = _base_declaration(type="databricks_16_4_med_general_fleet")
        declaration["cluster"]["type"] = "consolidation_s_general_cluster"
        declaration["validation"]["cluster"]["type"] = "consolidation_s_general_cluster"
        with pytest.raises(
            AssertionError, match="resolves to the same effective cluster"
        ):
            validator.validate(declaration)

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_allows_same_cluster_as_prod_with_overrides(self, validator):
        ConfigurationService._instance_cache.clear()
        declaration = _base_declaration(type="consolidation_s_general_cluster")
        declaration["cluster"]["type"] = "consolidation_s_general_cluster"
        declaration["cluster"]["custom_configurations"] = {
            "num_workers": 2,
            "runtime_engine": "PHOTON",
        }
        # A genuine resolved difference (num_workers 2 -> 3) keeps this a real
        # validation; the same-preset + distinguishing-override path stays allowed.
        declaration["validation"]["cluster"]["custom_configurations"] = {
            "num_workers": 3,
        }
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


class TestClusterValidationResolvedEquality:
    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_rejects_validation_resolving_to_prod_spec(self, validator):
        ConfigurationService._instance_cache.clear()
        declaration = _base_declaration(type="consolidation_s_general_cluster")
        declaration["cluster"]["type"] = "consolidation_s_general_cluster"
        declaration["cluster"]["custom_configurations"] = {
            "num_workers": 2,
            "runtime_engine": "PHOTON",
        }
        # validation.cluster only re-states an override prod already has -> resolves
        # to prod's effective spec, so it would validate nothing.
        declaration["validation"]["cluster"]["custom_configurations"] = {
            "runtime_engine": "PHOTON",
        }
        with pytest.raises(
            AssertionError, match="resolves to the same effective cluster"
        ):
            validator.validate(declaration)

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_allows_validation_with_real_resolved_diff(self, validator):
        ConfigurationService._instance_cache.clear()
        declaration = _base_declaration(type="consolidation_s_general_cluster")
        declaration["cluster"]["type"] = "consolidation_s_general_cluster"
        declaration["cluster"]["custom_configurations"] = {
            "num_workers": 2,
            "runtime_engine": "PHOTON",
        }
        declaration["validation"]["cluster"]["custom_configurations"] = {
            "num_workers": 3,
        }
        validator.validate(declaration)


class TestValidationResolvesToProdSpec:
    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_true_when_validation_restates_prod(self):
        ConfigurationService._instance_cache.clear()
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "r6g.xlarge",
            },
        }
        validation = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "r6g.xlarge",
            },
        }
        assert validation_resolves_to_prod_spec(
            prod, validation, ConfigurationService()
        )

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_false_for_driver_only_downsize(self):
        ConfigurationService._instance_cache.clear()
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "aws_attributes": {"ebs_volume_size": 200},
                "data_security_mode": "USER_ISOLATION",
                "num_workers": 3,
                "driver_node_type_id": "m6g.xlarge",
            },
        }
        # validation drops the prod driver override, so it resolves to the preset
        # default driver -- a real downsize, not a no-op.
        validation = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "aws_attributes": {"ebs_volume_size": 200},
                "data_security_mode": "USER_ISOLATION",
                "num_workers": 3,
            },
        }
        assert not validation_resolves_to_prod_spec(
            prod, validation, ConfigurationService()
        )


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

    def test_strips_prod_instance_topology_for_consolidation_validation(self):
        prod = {
            "type": "custom_cluster",
            "custom_configurations": {
                "spark_conf": {"spark.sql.caseSensitive": "true"},
                "node_type_id": "m5a.large",
                "driver_node_type_id": "m5a.xlarge",
                "num_workers": 1,
                "spark_version": "13.3.x-scala2.12",
            },
        }
        validation = {
            "type": "consolidation_xs_general_cluster",
            "custom_configurations": {
                "spark_version": "13.3.x-scala2.12",
                "num_workers": 1,
                "driver_node_type_id": "m6g.xlarge",
            },
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["type"] == "consolidation_xs_general_cluster"
        assert merged["custom_configurations"] == {
            "spark_conf": {"spark.sql.caseSensitive": "true"},
            "spark_version": "13.3.x-scala2.12",
            "num_workers": 1,
            "driver_node_type_id": "m6g.xlarge",
        }
        assert "node_type_id" not in merged["custom_configurations"]
        assert merged["custom_configurations"]["driver_node_type_id"] == "m6g.xlarge"

    def test_strips_prod_instance_topology_for_wonka_consolidation_validation(self):
        prod = {
            "type": "wonka_cluster",
            "custom_configurations": {
                "spark_conf": {"spark.sql.caseSensitive": "true"},
                "node_type_id": "r5a.8xlarge",
                "driver_node_type_id": "c5a.4xlarge",
                "num_workers": 2,
                "spark_version": "15.4.x-scala2.12",
            },
        }
        validation = {
            "type": "wonka_consolidation_m_general_cluster",
            "custom_configurations": {"num_workers": 3},
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["type"] == "wonka_consolidation_m_general_cluster"
        # wonka_consolidation_* must gate the same topology strip as
        # consolidation_*: prod instance types never leak into validation.
        assert "node_type_id" not in merged["custom_configurations"]
        assert "driver_node_type_id" not in merged["custom_configurations"]
        assert merged["custom_configurations"]["num_workers"] == 3
        assert merged["custom_configurations"]["spark_conf"] == {
            "spark.sql.caseSensitive": "true"
        }

    def test_strips_emr_only_keys_for_emr_to_databricks_validation(self):
        prod = {
            "type": "emr_7_12_consolidation_m_memory_cluster",
            "custom_configurations": {
                "core_nodes": {"instance_count": 1},
                "task_nodes": {"instance_count": 2},
                "num_task_workers": 2,
                "spark_conf": {"spark.driver.memory": "8g"},
            },
        }
        validation = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {
                "driver_node_type_id": "r6g.2xlarge",
                "node_type_id": "m6g.xlarge",
            },
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"] == {
            "spark_conf": {"spark.driver.memory": "8g"},
            "driver_node_type_id": "r6g.2xlarge",
            "node_type_id": "m6g.xlarge",
        }

    def test_keeps_emr_keys_for_emr_to_emr_validation(self):
        prod = {
            "type": "emr_7_12_consolidation_m_memory_cluster",
            "custom_configurations": {
                "core_nodes": {"instance_count": 1},
                "task_nodes": {"instance_count": 2},
                "spark_conf": {"spark.driver.memory": "8g"},
            },
        }
        validation = {
            "type": "emr_7_12_med_general_cluster",
            "custom_configurations": {"num_workers": 2},
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"] == {
            "core_nodes": {"instance_count": 1},
            "task_nodes": {"instance_count": 2},
            "spark_conf": {"spark.driver.memory": "8g"},
            "num_workers": 2,
        }

    def test_strips_databricks_keys_for_databricks_to_emr_validation(self):
        prod = {
            "type": "consolidation_xl_memory_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "r6g.2xlarge",
                "node_type_id": "r6g.2xlarge",
                "runtime_engine": "PHOTON",
                "spark_conf": {"spark.sql.shuffle.partitions": "200"},
            },
        }
        validation = {
            "type": "emr_7_12_consolidation_xl_memory_cluster",
            "custom_configurations": {
                "core_nodes": {"node_type_id": "r7g.8xlarge", "instance_count": 1},
                "task_nodes": {"node_type_id": "r7g.8xlarge", "instance_count": 2},
            },
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert "databricks_conn_id" not in merged
        assert merged["custom_configurations"] == {
            "spark_conf": {"spark.sql.shuffle.partitions": "200"},
            "core_nodes": {"node_type_id": "r7g.8xlarge", "instance_count": 1},
            "task_nodes": {"node_type_id": "r7g.8xlarge", "instance_count": 2},
        }

    def test_deep_merges_spark_conf_for_databricks_to_emr_validation(self):
        prod = {
            "type": "consolidation_s_general_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "num_workers": 3,
                "spark_conf": {
                    "spark.sql.session.timeZone": "America/Sao_Paulo",
                    "spark.sql.shuffle.partitions": "200",
                },
            },
        }
        validation = {
            "type": "emr_7_12_consolidation_s_general_cluster",
            "custom_configurations": {
                "master_node_type_id": "r7g.xlarge",
                "spark_conf": {
                    "spark.driver.memory": "8g",
                    "spark.driver.memoryOverhead": "2g",
                },
            },
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"]["spark_conf"] == {
            "spark.sql.session.timeZone": "America/Sao_Paulo",
            "spark.sql.shuffle.partitions": "200",
            "spark.driver.memory": "8g",
            "spark.driver.memoryOverhead": "2g",
        }

    def test_strips_databricks_spark_conf_for_databricks_to_emr_validation(self):
        prod = {
            "type": "consolidation_s_general_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod",
                    "spark.sql.shuffle.partitions": "200",
                },
            },
        }
        validation = {
            "type": "emr_7_12_consolidation_s_general_fleet_cluster",
            "custom_configurations": {
                "task_nodes": {"target_spot": 1},
            },
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"]["spark_conf"] == {
            "spark.sql.shuffle.partitions": "200",
        }

    def test_omits_spark_conf_when_prod_only_has_databricks_keys(self):
        prod = {
            "type": "consolidation_xs_general_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod",
                },
            },
        }
        validation = {
            "type": "emr_7_12_consolidation_xs_general_fleet_cluster",
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert "spark_conf" not in merged.get("custom_configurations", {})

    def test_strips_prod_num_workers_for_single_node_validation(self):
        prod = {
            "type": "consolidation_l_memory_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "r6g.8xlarge",
                "spark_version": "16.4.x-scala2.12",
            },
        }
        validation = {
            "type": "consolidation_l_memory_single_node_cluster",
            "custom_configurations": {},
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert "num_workers" not in merged.get("custom_configurations", {})

    def test_strips_prod_photon_when_validation_custom_empty(self):
        prod = {
            "type": "consolidation_m_general_single_node_cluster",
            "custom_configurations": {"runtime_engine": "PHOTON"},
        }
        validation = {
            "type": "consolidation_m_general_single_node_cluster",
            "custom_configurations": {},
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert "runtime_engine" not in merged.get("custom_configurations", {})

    def test_keeps_prod_photon_when_validation_has_other_overrides(self):
        prod = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {
                "num_workers": 2,
                "runtime_engine": "PHOTON",
            },
        }
        validation = {
            "type": "consolidation_s_general_cluster",
            "custom_configurations": {"num_workers": 3},
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"]["runtime_engine"] == "PHOTON"
        assert merged["custom_configurations"]["num_workers"] == 3

    def test_strips_master_node_type_id_for_consolidation_validation(self):
        prod = {
            "type": "custom_cluster",
            "custom_configurations": {
                "node_type_id": "m7g.2xlarge",
                "master_node_type_id": "m7g.xlarge",
                "num_workers": 2,
            },
        }
        validation = {
            "type": "consolidation_s_memory_cluster",
            "custom_configurations": {
                "num_workers": 2,
                "master_node_type_id": "m6g.xlarge",
            },
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"] == {
            "num_workers": 2,
            "master_node_type_id": "m6g.xlarge",
        }
        assert "node_type_id" not in merged["custom_configurations"]

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_resolved_alert_manager_validation_cluster_uses_graviton_topology(self):
        prod = {
            "type": "custom_cluster",
            "custom_configurations": {
                "spark_conf": {"spark.sql.caseSensitive": "true"},
                "node_type_id": "m5a.large",
                "driver_node_type_id": "m5a.xlarge",
                "num_workers": 1,
                "spark_version": "13.3.x-scala2.12",
            },
        }
        validation = {
            "type": "consolidation_xs_general_cluster",
            "custom_configurations": {
                "spark_version": "13.3.x-scala2.12",
                "num_workers": 1,
                "driver_node_type_id": "m6g.xlarge",
            },
        }
        merged = merge_validation_cluster_args(prod, validation)
        resolved = merge_cluster_configuration(merged, ConfigurationService())
        assert resolved["node_type_id"].startswith("m7g.")
        assert resolved["driver_node_type_id"] == "m6g.xlarge"

    def test_strips_prod_num_workers_for_multi_node_type_only_validation(self):
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "m7g.xlarge",
            },
        }
        validation = {
            "type": "consolidation_xs_memory_cluster",
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert "custom_configurations" not in merged

    def test_clears_custom_configurations_when_both_empty_after_strip(self):
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "driver_node_type_id": "m7g.xlarge",
            },
        }
        validation = {
            "type": "consolidation_xs_memory_cluster",
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert "custom_configurations" not in merged

    def test_type_only_validation_keeps_non_topology_prod_custom(self):
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "single_user_name": "user@example.com",
                "data_security_mode": "SINGLE_USER",
                "spark_conf": {
                    "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod"
                },
                "num_workers": 3,
                "driver_node_type_id": "m7g.xlarge",
            },
        }
        validation = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new",
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"] == {
            "single_user_name": "user@example.com",
            "data_security_mode": "SINGLE_USER",
            "spark_conf": {
                "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod"
            },
        }
        assert "num_workers" not in merged["custom_configurations"]
        assert "driver_node_type_id" not in merged["custom_configurations"]

    def test_keeps_explicit_validation_num_workers_for_keep_worker_count(self):
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "m6g.xlarge",
            },
        }
        validation = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {"num_workers": 3},
        }
        merged = merge_validation_cluster_args(prod, validation)
        assert merged["custom_configurations"]["num_workers"] == 3
        assert "driver_node_type_id" not in merged["custom_configurations"]


class TestClusterValidationTypeOnlyPresetDefaults:
    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_allows_enrich_fairness_style_type_only_validation(self, validator):
        ConfigurationService._instance_cache.clear()
        declaration = _base_declaration(type="consolidation_xs_memory_cluster")
        declaration["cluster"]["type"] = "consolidation_xs_memory_cluster"
        declaration["cluster"]["custom_configurations"] = {
            "single_user_name": "user@example.com",
            "data_security_mode": "SINGLE_USER",
            "spark_conf": {
                "spark.databricks.sql.initial.catalog.namespace": "quintoandar_prod"
            },
            "num_workers": 3,
            "driver_node_type_id": "m7g.xlarge",
        }
        declaration["validation"]["cluster"] = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new",
        }
        declaration["validation"]["allow_custom_spark_job"] = True
        validator.validate(declaration)

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_allows_enrich_marketing_style_type_only_validation(self, validator):
        ConfigurationService._instance_cache.clear()
        declaration = _base_declaration(type="consolidation_xs_memory_cluster")
        declaration["cluster"]["type"] = "consolidation_xs_memory_cluster"
        declaration["cluster"]["custom_configurations"] = {
            "num_workers": 3,
            "driver_node_type_id": "m7g.xlarge",
        }
        declaration["validation"]["cluster"] = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new_env",
        }
        validator.validate(declaration)

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_allows_twilio_style_driver_only_downsize(self, validator):
        ConfigurationService._instance_cache.clear()
        declaration = _base_declaration(type="consolidation_xs_memory_cluster")
        declaration["cluster"]["type"] = "consolidation_xs_memory_cluster"
        declaration["cluster"]["custom_configurations"] = {
            "driver_node_type_id": "m7g.xlarge",
        }
        declaration["validation"]["cluster"] = {
            "type": "consolidation_xs_memory_cluster",
            "databricks_conn_id": "databricks_new",
            "custom_libraries": [{"whl": "s3://bucket/client.whl"}],
        }
        declaration["validation"]["allow_custom_spark_job"] = True
        validator.validate(declaration)

    @mock.patch.dict(os.environ, {"ENVIRONMENT": "prod"})
    def test_type_only_resolves_to_preset_workers_not_prod_override(self):
        ConfigurationService._instance_cache.clear()
        prod = {
            "type": "consolidation_xs_memory_cluster",
            "custom_configurations": {
                "num_workers": 3,
                "driver_node_type_id": "m7g.xlarge",
            },
        }
        validation = {"type": "consolidation_xs_memory_cluster"}
        merged = merge_validation_cluster_args(prod, validation)
        resolved = merge_cluster_configuration(merged, ConfigurationService())
        assert resolved["num_workers"] == 2
        assert resolved["driver_node_type_id"] == "r7g.large"
        assert not validation_resolves_to_prod_spec(
            prod, validation, ConfigurationService()
        )
