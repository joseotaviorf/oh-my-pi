import copy
import os
from unittest.mock import Mock, patch

import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.wonka_workflow import (
    WonkaWorkflow,
)

_WONKA_CLUSTER_PRESET = {
    "spark_version": "16.4.x-scala2.12",
    "databricks_conn_id": "databricks_new",
    "spark_env_vars": {"SPARK_RUNTIME": "databricks"},
}
_WONKA_CLUSTER_EMR_PRESET = {
    "spark_version": "emr-7.12.0",
    "init_scripts": [
        {"s3": {"destination": "s3://artifacts/emr_init_script.sh"}, "args": ["a"]},
        {"s3": {"destination": "s3://artifacts/install_pex_generic.sh"}, "args": []},
    ],
    "spark_env_vars": {"SPARK_RUNTIME": "emr"},
}
_ARTIFACT_PATH = "s3://wonka/artifacts/abc123"


class TestWonkaWorkflowGetDeepUpdatedDict:
    def test_empty_new_values_returns_deep_copy_of_old(self):
        old = {"a": 1, "nested": {"b": 2}}
        merged = WonkaWorkflow._get_deep_updated_dict(old, {})
        assert merged == old
        assert merged is not old
        assert merged["nested"] is not old["nested"]

    def test_none_new_values_same_as_empty_dict(self):
        old = {"x": 1}
        merged = WonkaWorkflow._get_deep_updated_dict(old, None)
        assert merged == old
        assert merged is not old

    def test_nested_dicts_are_merged_recursively(self):
        old = {
            "custom_configurations": {
                "spark_version": "13.3.x",
                "autoscale": {"min_workers": 1, "max_workers": 4},
            }
        }
        new = {
            "custom_configurations": {
                "spark_version": "15.4.x",
                "driver_node_type_id": "m5a.xlarge",
            }
        }
        merged = WonkaWorkflow._get_deep_updated_dict(old, new)
        assert merged["custom_configurations"]["spark_version"] == "15.4.x"
        assert merged["custom_configurations"]["driver_node_type_id"] == "m5a.xlarge"
        assert merged["custom_configurations"]["autoscale"] == {
            "min_workers": 1,
            "max_workers": 4,
        }

    def test_scalar_replaces_nested_dict(self):
        old = {"k": {"inner": 1}}
        merged = WonkaWorkflow._get_deep_updated_dict(old, {"k": "replaced"})
        assert merged["k"] == "replaced"

    def test_list_replaces_prior_value(self):
        old = {"libs": [1, 2]}
        merged = WonkaWorkflow._get_deep_updated_dict(old, {"libs": [3]})
        assert merged["libs"] == [3]

    def test_does_not_mutate_inputs(self):
        preset = {
            "databricks_conn_id": "databricks_new",
            "custom_configurations": {"spark_version": "13.3.x"},
        }
        declaration = {
            "type": "wonka_cluster",
            "custom_configurations": {"spark_version": "15.4.x"},
        }
        preset_copy = copy.deepcopy(preset)
        declaration_copy = copy.deepcopy(declaration)
        WonkaWorkflow._get_deep_updated_dict(preset, declaration)
        assert preset == preset_copy
        assert declaration == declaration_copy

    def test_preset_keys_remain_when_not_overridden(self):
        preset = {
            "databricks_conn_id": "databricks_new",
            "custom_libraries": [{"maven": {"coordinates": "a:b:1"}}],
        }
        declaration = {"type": "wonka_cluster", "custom_configurations": {}}
        merged = WonkaWorkflow._get_deep_updated_dict(preset, declaration)
        assert merged["databricks_conn_id"] == "databricks_new"
        assert merged["type"] == "wonka_cluster"
        assert merged["custom_libraries"] == preset["custom_libraries"]

    def test_spark_conf_promotion_merge(self):
        """Same shape as __init__: merge top-level spark_conf from nested custom_configurations."""
        merged_base = {
            "custom_configurations": {
                "spark_conf": {"spark.foo": "1"},
                "spark_version": "15.4.x",
            }
        }
        custom_spark_conf = merged_base["custom_configurations"]["spark_conf"]
        final = WonkaWorkflow._get_deep_updated_dict(
            merged_base, {"spark_conf": custom_spark_conf}
        )
        assert final["spark_conf"] == {"spark.foo": "1"}
        assert final["custom_configurations"]["spark_conf"] == {"spark.foo": "1"}

    def test_old_values_none_treated_as_empty_dict(self):
        merged = WonkaWorkflow._get_deep_updated_dict(None, {"a": 1})
        assert merged == {"a": 1}

    @pytest.mark.parametrize("bad_new", [42, "x", [1]])
    def test_new_values_must_be_dict_or_none(self, bad_new):
        with pytest.raises(TypeError, match="new_values must be a dict"):
            WonkaWorkflow._get_deep_updated_dict({}, bad_new)

    @pytest.mark.parametrize("bad_old", [42, "x", [1]])
    def test_old_values_must_be_dict_or_none(self, bad_old):
        with pytest.raises(TypeError, match="old_values must be a dict"):
            WonkaWorkflow._get_deep_updated_dict(bad_old, {})


class TestWonkaWorkflowClusterPresetSelection:
    @pytest.fixture
    def config_presets(self):
        return {
            "wonka_cluster": _WONKA_CLUSTER_PRESET,
            "wonka_cluster_emr": _WONKA_CLUSTER_EMR_PRESET,
        }

    def _workflow(self, cluster_args, config_presets):
        dag_args = {"name": "test-wonka", "owner": "MLOps"}
        workflow_args = {"type": "wonka", "wonka_config": {"name": "test_wonka"}}
        config_service = Mock()
        config_service.get_config = Mock(side_effect=lambda key: config_presets[key])
        with patch(
            "bietlejuice.base.airflow.dag_builders.main_builder.workflows.base_workflow.ConfigurationService",
            return_value=config_service,
        ):
            return WonkaWorkflow(dag_args, workflow_args, cluster_args, None)

    def test_loads_emr_preset_when_type_is_wonka_cluster_emr(self, config_presets):
        workflow = self._workflow({"type": "wonka_cluster_emr"}, config_presets)
        assert workflow.cluster_args["spark_version"] == "emr-7.12.0"
        assert workflow.cluster_args["spark_env_vars"]["SPARK_RUNTIME"] == "emr"

    def test_loads_default_preset_when_type_omitted(self, config_presets):
        workflow = self._workflow({}, config_presets)
        assert workflow.cluster_args["spark_version"] == "16.4.x-scala2.12"
        assert workflow.cluster_args["databricks_conn_id"] == "databricks_new"

    def test_loads_wonka_cluster_when_type_explicit(self, config_presets):
        workflow = self._workflow({"type": "wonka_cluster"}, config_presets)
        assert workflow.cluster_args["spark_version"] == "16.4.x-scala2.12"

    @patch.dict(os.environ, {"ENVIRONMENT": "forno"}, clear=False)
    def test_emr_preset_allowed_in_forno(self, config_presets):
        workflow = self._workflow({"type": "wonka_cluster_emr"}, config_presets)
        assert workflow.cluster_args["spark_version"] == "emr-7.12.0"

    @patch.dict(os.environ, {"ENVIRONMENT": "prod"}, clear=False)
    def test_emr_preset_raises_in_prod(self, config_presets):
        with pytest.raises(RuntimeError, match="Wonka EMR is not enabled in prod"):
            self._workflow({"type": "wonka_cluster_emr"}, config_presets)

    @patch.dict(os.environ, {"ENVIRONMENT": "prod"}, clear=False)
    def test_databricks_preset_allowed_in_prod(self, config_presets):
        workflow = self._workflow({"type": "wonka_cluster"}, config_presets)
        assert workflow.cluster_args["spark_version"] == "16.4.x-scala2.12"


class TestWonkaWorkflowEmrBootstrapArgInjection:
    @pytest.fixture
    def workflow(self):
        return WonkaWorkflow.__new__(WonkaWorkflow)

    def test_patch_emr_install_pex_sets_args_by_script_suffix(self):
        cluster_configuration = copy.deepcopy(_WONKA_CLUSTER_EMR_PRESET)
        WonkaWorkflow._patch_emr_install_pex_bootstrap_args(
            cluster_configuration, _ARTIFACT_PATH
        )
        install_pex = cluster_configuration["init_scripts"][1]
        assert install_pex["args"] == [_ARTIFACT_PATH]

    def test_patch_emr_install_pex_leaves_other_scripts_unchanged(self):
        cluster_configuration = copy.deepcopy(_WONKA_CLUSTER_EMR_PRESET)
        WonkaWorkflow._patch_emr_install_pex_bootstrap_args(
            cluster_configuration, _ARTIFACT_PATH
        )
        assert cluster_configuration["init_scripts"][0]["args"] == ["a"]

    def test_set_env_vars_patches_bootstrap_args_on_emr(self, workflow):
        task = Mock()
        task.cluster_configuration = copy.deepcopy(_WONKA_CLUSTER_EMR_PRESET)
        WonkaWorkflow._WonkaWorkflow__set_env_vars_from_dag_args(
            workflow, task, {"artifact_path": _ARTIFACT_PATH}
        )
        assert (
            task.cluster_configuration["spark_env_vars"]["PACKAGE_PATH"]
            == _ARTIFACT_PATH
        )
        assert task.cluster_configuration["init_scripts"][1]["args"] == [_ARTIFACT_PATH]

    def test_set_env_vars_does_not_patch_bootstrap_args_on_databricks(self, workflow):
        task = Mock()
        task.cluster_configuration = {
            "spark_version": "16.4.x-scala2.12",
            "spark_env_vars": {},
            "init_scripts": [
                {
                    "s3": {"destination": "s3://artifacts/install_pex_generic.sh"},
                    "args": [],
                }
            ],
        }
        WonkaWorkflow._WonkaWorkflow__set_env_vars_from_dag_args(
            workflow, task, {"artifact_path": _ARTIFACT_PATH}
        )
        assert (
            task.cluster_configuration["spark_env_vars"]["PACKAGE_PATH"]
            == _ARTIFACT_PATH
        )
        assert task.cluster_configuration["init_scripts"][0]["args"] == []
