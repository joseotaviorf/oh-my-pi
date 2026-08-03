"""Guards for custom_configurations merging.

Regression context: ``HierarchicalConf._deep_update`` only recurses into *truthy*
mappings, so ``spark_conf: {}`` in a declaration replaced the preset's whole
``spark_conf`` instead of no-op'ing. On EMR that silently dropped
``spark.sql.catalogImplementation: hive`` — making Glue-backed JSON/Parquet tables
unresolvable (`TABLE_OR_VIEW_NOT_FOUND`) — plus every driver/executor override.
"""

from bietlejuice.base.airflow.cluster_config_resolver import (
    apply_custom_configurations,
    merge_cluster_configuration,
    prune_empty_mappings,
)


class _FakeConfigService:
    """Mimics HierarchicalConf._deep_update, including its empty-mapping quirk."""

    def __init__(self, configs=None):
        self._configs = configs or {}

    def get_config(self, key):
        return self._configs[key]

    def _deep_update(self, source, overrides):
        from collections.abc import Mapping

        for key, value in overrides.items():
            if isinstance(value, Mapping) and value:
                source[key] = self._deep_update(source.get(key, {}), value)
            else:
                source[key] = overrides[key]
        return source


def test_prune_empty_mappings_drops_empty_dict():
    assert prune_empty_mappings({"spark_conf": {}, "num_workers": 4}) == {
        "num_workers": 4
    }


def test_prune_empty_mappings_drops_nested_only_empty_dicts():
    assert prune_empty_mappings({"aws_attributes": {"nested": {}}}) == {}


def test_prune_empty_mappings_keeps_populated_and_falsy_scalars():
    overrides = {
        "spark_conf": {"spark.sql.shuffle.partitions": "200"},
        "num_workers": 0,
        "label": "",
        "flag": False,
        "nothing": None,
    }

    assert prune_empty_mappings(overrides) == overrides


def test_prune_empty_mappings_keeps_empty_list():
    # Only mappings have the wipe-vs-merge ambiguity; an empty list is a real value.
    assert prune_empty_mappings({"init_scripts": []}) == {"init_scripts": []}


def test_apply_custom_configurations_empty_spark_conf_preserves_preset():
    preset = {
        "spark_conf": {
            "spark.sql.catalogImplementation": "hive",
            "spark.executor.memory": "48g",
        }
    }

    merged = apply_custom_configurations(
        preset, {"spark_conf": {}}, _FakeConfigService()
    )

    assert merged["spark_conf"] == {
        "spark.sql.catalogImplementation": "hive",
        "spark.executor.memory": "48g",
    }


def test_apply_custom_configurations_partial_spark_conf_overrides_only_given_keys():
    preset = {
        "spark_conf": {
            "spark.sql.catalogImplementation": "hive",
            "spark.executor.memory": "48g",
        }
    }

    merged = apply_custom_configurations(
        preset, {"spark_conf": {"spark.executor.memory": "16g"}}, _FakeConfigService()
    )

    assert merged["spark_conf"] == {
        "spark.sql.catalogImplementation": "hive",
        "spark.executor.memory": "16g",
    }


def test_merge_cluster_configuration_empty_spark_conf_keeps_emr_catalog_implementation():
    config_service = _FakeConfigService(
        {
            "emr_7_12_consolidation_l_memory_fleet_cluster": {
                "spark_conf": {
                    "spark.sql.catalogImplementation": "hive",
                    "spark.driver.memory": "12g",
                },
            }
        }
    )
    cluster_args = {
        "type": "emr_7_12_consolidation_l_memory_fleet_cluster",
        "custom_configurations": {
            "spark_conf": {},
            "core_nodes": {"target_on_demand": 2},
        },
    }

    merged = merge_cluster_configuration(cluster_args, config_service)

    assert merged["spark_conf"]["spark.sql.catalogImplementation"] == "hive"
    assert merged["spark_conf"]["spark.driver.memory"] == "12g"
    assert merged["core_nodes"] == {"target_on_demand": 2}


def test_merge_cluster_configuration_does_not_mutate_shared_preset():
    preset = {"spark_conf": {"spark.driver.memory": "12g"}}
    config_service = _FakeConfigService({"some_cluster": preset})
    cluster_args = {
        "type": "some_cluster",
        "custom_configurations": {"spark_conf": {"spark.driver.memory": "4g"}},
    }

    merge_cluster_configuration(cluster_args, config_service)

    assert preset["spark_conf"]["spark.driver.memory"] == "12g"
