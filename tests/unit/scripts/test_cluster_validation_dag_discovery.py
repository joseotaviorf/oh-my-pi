"""Unit tests for cluster validation DAG discovery (bi-etl + Wonka)."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT))

from scripts.cluster_validation_dag_discovery import (  # noqa: E402
    discover_validation_dags,
    discover_wonka_validation_dags,
    filter_validation_dags,
)


def _write_wonka_prod(tmp_path: Path, job_dir: str, *, with_validation: bool) -> Path:
    job_root = tmp_path / "jobs" / "wonka" / job_dir / "configs"
    job_root.mkdir(parents=True)
    doc = {
        "dag": {"name": job_dir.replace("-", "_")},
        "workflow": {
            "type": "wonka",
            "layer": "wonka",
            "wonka_config": {"name": job_dir.replace("-", "_")},
        },
        "cluster": {"type": "wonka_cluster"},
    }
    if with_validation:
        doc["validation"] = {
            "cluster": {
                "type": "consolidation_memory",
                "custom_configurations": {"node_type_id": "r7g.8xlarge"},
            }
        }
    prod_yml = job_root / "prod.yml"
    prod_yml.write_text(yaml.dump(doc), encoding="utf-8")
    return prod_yml


class TestDiscoverWonkaValidationDags:
    def test_discovers_validation_dags(self, tmp_path: Path):
        _write_wonka_prod(tmp_path, "house-main", with_validation=True)
        _write_wonka_prod(tmp_path, "user-visits", with_validation=False)

        discovered = discover_wonka_validation_dags(tmp_path)
        assert len(discovered) == 1
        assert discovered[0].line == "wonka"
        assert discovered[0].dag_id == "quintoml.wonka.house_main__validation"
        assert discovered[0].original_dag_id == "quintoml.wonka.house_main"

    def test_filter_by_wonka_line(self, tmp_path: Path):
        _write_wonka_prod(tmp_path, "house-main", with_validation=True)
        discovered = discover_wonka_validation_dags(tmp_path)
        filtered = filter_validation_dags(discovered, lines="wonka")
        assert len(filtered) == 1
        filtered_out = filter_validation_dags(discovered, lines="people")
        assert filtered_out == []


class TestDiscoverValidationDagsCombined:
    def test_omits_wonka_when_quintoml_root_not_passed(self, tmp_path: Path) -> None:
        dags_root = tmp_path / "dags"
        agents_dir = dags_root / "agents" / "dw_agent"
        agents_dir.mkdir(parents=True)
        (agents_dir / "dw_agent_cluster.yml").write_text(
            "cluster:\n  type: databricks_16_4_med_general_cluster\n"
            "validation:\n  cluster:\n    type: consolidation_s_general_cluster\n",
            encoding="utf-8",
        )
        _write_wonka_prod(tmp_path, "house-main", with_validation=True)

        discovered = discover_validation_dags(dags_root)
        assert len(discovered) == 1
        assert discovered[0].dag_id == "bietlejuice.dw_agent__validation"

    def test_includes_wonka_when_quintoml_root_passed(self, tmp_path: Path) -> None:
        dags_root = tmp_path / "dags"
        agents_dir = dags_root / "agents" / "dw_agent"
        agents_dir.mkdir(parents=True)
        (agents_dir / "dw_agent_cluster.yml").write_text(
            "cluster:\n  type: databricks_16_4_med_general_cluster\n"
            "validation:\n  cluster:\n    type: consolidation_s_general_cluster\n",
            encoding="utf-8",
        )
        _write_wonka_prod(tmp_path, "house-main", with_validation=True)

        discovered = discover_validation_dags(dags_root, quintoml_root=tmp_path)
        assert len(discovered) == 2
        assert {item.dag_id for item in discovered} == {
            "bietlejuice.dw_agent__validation",
            "quintoml.wonka.house_main__validation",
        }
