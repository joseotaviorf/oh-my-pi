"""Regression guard: EMR cluster spark_conf anchor keeps the small-file write-side defaults.

Parses the YAML directly (no ConfigurationService/HierarchicalConf) so this stays a
cheap, environment-independent sanity check rather than a full config-resolution test.
"""

from pathlib import Path

import pytest
import yaml

_CONFIG_DIR = Path(__file__).parents[4] / "src" / "bietlejuice" / "config"

_EXPECTED_SPARK_CONF_DEFAULTS = {
    "spark.sql.adaptive.enabled": "true",
    "spark.sql.adaptive.coalescePartitions.enabled": "true",
    "spark.sql.files.maxPartitionBytes": "268435456",
    "spark.sql.adaptive.advisoryPartitionSizeInBytes": "268435456",
    "spark.databricks.delta.optimizeWrite.enabled": "true",
}

_EXPECTED_METRICS_KEYS = (
    "spark.plugins",
    "spark.cernSparkPlugin.cloudFsName",
    "spark.cernSparkPlugin.registerOnDriver",
    "spark.metrics.conf.*.sink.graphite.class",
    "spark.metrics.conf.*.sink.graphite.host",
    "spark.metrics.conf.*.sink.graphite.port",
    "spark.metrics.conf.*.source.jvm.class",
    "spark.metrics.namespace",
)
_EXPECTED_GRAPHITE_HOST = {
    "prod_conf.yml": "graphite-exporter.svc.core-prd.habitat.zone",
    "forno_conf.yml": "graphite-exporter.apps.core-frn.habitat.zone",
}
_EXPECTED_PLUGINS = "ch.cern.CloudFSMetrics,br.com.quintoandar.GangliaMetrics"


def _load_emr_cluster_base_spark_conf(conf_file_name: str) -> dict:
    path = _CONFIG_DIR / conf_file_name
    # YAML anchors/aliases (`&x`, `*x`, `<<:`) resolve naturally via safe_load.
    raw = yaml.safe_load(path.read_text())
    return raw["emr_cluster_base"]["spark_conf"]


@pytest.mark.parametrize("conf_file_name", ["prod_conf.yml", "forno_conf.yml"])
class TestEmrClusterSparkConfDefaults:
    def test_write_side_small_file_defaults_present(self, conf_file_name):
        spark_conf = _load_emr_cluster_base_spark_conf(conf_file_name)

        for key, expected_value in _EXPECTED_SPARK_CONF_DEFAULTS.items():
            assert key in spark_conf, f"{key} missing from {conf_file_name}"
            assert str(spark_conf[key]) == expected_value, (
                f"{key} in {conf_file_name} is {spark_conf[key]!r}, "
                f"expected {expected_value!r}"
            )

    def test_metrics_plugin_keys_present(self, conf_file_name):
        spark_conf = _load_emr_cluster_base_spark_conf(conf_file_name)

        for key in _EXPECTED_METRICS_KEYS:
            assert key in spark_conf, f"{key} missing from {conf_file_name}"

        assert spark_conf["spark.plugins"] == _EXPECTED_PLUGINS
        assert (
            spark_conf["spark.metrics.conf.*.sink.graphite.host"]
            == _EXPECTED_GRAPHITE_HOST[conf_file_name]
        )
