"""Unit tests for WonkaWorkflow._get_deep_updated_dict."""

import copy

import pytest

from bietlejuice.base.airflow.dag_builders.main_builder.workflows.wonka_workflow import (
    WonkaWorkflow,
)


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
