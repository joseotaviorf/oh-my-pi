"""Unit tests for Wonka 1:1 Gen7 validation block generation."""

from __future__ import annotations

from pathlib import Path

import yaml

from scripts.ci_cd.airflow_dag_builder.cluster_validation_mapping import (
    build_validation_cluster_spec,
)
from scripts.ci_cd.airflow_dag_builder.wonka_config_paths import wonka_airflow_dag_id
from scripts.ci_cd.airflow_dag_builder.wonka_validation_config import (
    validation_doc_from_spec,
    write_validation_to_wonka_prod_yml,
)

pytest_plugins = ["test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env"]

HOUSE_MAIN_DECLARATION = {
    "dag": {"name": "house_main"},
    "workflow": {
        "type": "wonka",
        "layer": "wonka",
        "wonka_config": {"name": "house_main"},
    },
    "cluster": {
        "type": "wonka_cluster",
        "custom_configurations": {
            "spark_version": "15.4.x-scala2.12",
            "driver_node_type_id": "c5a.4xlarge",
            "node_type_id": "r5a.8xlarge",
            "num_workers": 2,
        },
    },
}


class TestWonkaValidationBlockGeneration:
    def test_build_validation_spec_maps_x86_to_graviton(self):
        spec = build_validation_cluster_spec(
            cluster_args=HOUSE_MAIN_DECLARATION["cluster"],
            declaration=HOUSE_MAIN_DECLARATION,
        )
        assert spec is not None
        custom = spec.custom_configurations or {}
        assert custom["driver_node_type_id"] == "c7g.4xlarge"
        # The wonka_consolidation_* preset carries 15.4 itself, so the
        # spark_version override disappears from the generated block.
        assert "spark_version" not in custom
        assert spec.cluster_type.startswith("wonka_consolidation_")

    def test_validation_doc_from_spec_shape(self):
        spec = build_validation_cluster_spec(
            cluster_args=HOUSE_MAIN_DECLARATION["cluster"],
            declaration=HOUSE_MAIN_DECLARATION,
        )
        assert spec is not None
        doc = validation_doc_from_spec(spec)
        assert "cluster" in doc
        assert doc["cluster"]["type"].startswith("wonka_consolidation_")

    def test_wonka_airflow_dag_id(self):
        assert (
            wonka_airflow_dag_id(HOUSE_MAIN_DECLARATION) == "quintoml.wonka.house_main"
        )

    def test_emr_wonka_cluster_skipped(self, tmp_path: Path):
        declaration = {
            **HOUSE_MAIN_DECLARATION,
            "cluster": {"type": "wonka_cluster_emr"},
        }
        prod_yml = tmp_path / "prod.yml"
        prod_yml.write_text(yaml.dump(declaration), encoding="utf-8")
        spec = build_validation_cluster_spec(
            cluster_args=declaration["cluster"],
            declaration=declaration,
        )
        assert spec is None

    def test_wonka_prod_yml_round_trip_carries_no_runtime_boilerplate(
        self, tmp_path: Path
    ):
        spec = build_validation_cluster_spec(
            cluster_args=HOUSE_MAIN_DECLARATION["cluster"],
            declaration=HOUSE_MAIN_DECLARATION,
        )
        assert spec is not None
        doc = validation_doc_from_spec(spec)
        assert doc["cluster"]["type"].startswith("wonka_consolidation_")

        prod_yml = tmp_path / "prod.yml"
        prod_yml.write_text(yaml.dump(HOUSE_MAIN_DECLARATION), encoding="utf-8")
        write_validation_to_wonka_prod_yml(prod_yml, doc)

        written = yaml.safe_load(prod_yml.read_text(encoding="utf-8"))
        validation = written["validation"]
        assert validation["cluster"]["type"].startswith("wonka_consolidation_")
        # The wonka preset carries the wonka runtime; the serialized block
        # must not restate spark_env_vars at any nesting level.
        assert not _contains_key(validation, "spark_env_vars")


def _contains_key(node: object, key: str) -> bool:
    if isinstance(node, dict):
        return any(k == key or _contains_key(v, key) for k, v in node.items())
    if isinstance(node, list):
        return any(_contains_key(item, key) for item in node)
    return False
