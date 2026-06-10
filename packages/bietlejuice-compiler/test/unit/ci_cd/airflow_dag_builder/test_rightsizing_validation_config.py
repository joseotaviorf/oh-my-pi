"""Unit tests for rightsizing_validation_config."""

from __future__ import annotations

from dataclasses import dataclass, field

from scripts.ci_cd.airflow_dag_builder.rightsizing_validation_config import (
    generate_validation_config,
    remove_validation_from_cluster_file,
    write_validation_cluster_file,
)

pytest_plugins = ["test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env"]


@dataclass
class _Projected:
    est_cost_delta_pct: float | None = -20.0
    blocking_reason: str | None = None


@dataclass
class _Rec:
    dag_id: str
    cohort: str
    confidence: str
    actions: str
    current_preset: str | None
    current_driver_node_type: str = "m6g.xlarge"
    current_worker_node_type: str | None = "m6g.xlarge"
    current_worker_count: int | None = 2
    recommended_preset: str | None = None
    rec_driver_node_type: str | None = None
    rec_worker_node_type: str | None = None
    rec_worker_count: int | None = None
    num_workers_override: int | None = None
    driver_override_node_type_id: str | None = None
    rec_runtime_engine: str | None = None
    driver_action: str | None = ""
    worker_action: str | None = ""
    projected: _Projected = field(default_factory=_Projected)


class TestGenerateValidationConfig:
    def test_skips_when_recommended_preset_matches_prod_type(self):
        rec = _Rec(
            dag_id="bietlejuice.test_dag",
            cohort="collapse_to_single",
            confidence="high",
            actions="collapse_to_single",
            current_preset="consolidation_m_memory_cluster",
            recommended_preset="consolidation_m_memory_cluster",
            driver_override_node_type_id="r6g.xlarge",
        )

        assert generate_validation_config(rec) is None

    def test_single_node_omits_preset_default_topology(self, tmp_path, monkeypatch):
        dag_dir = tmp_path / "dags" / "growth" / "enrich_semrush_classified"
        dag_dir.mkdir(parents=True)
        (dag_dir / "enrich_semrush_classified_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_xs_general_single_node_cluster\n"
            "  databricks_conn_id: databricks_new_env\n"
            "  custom_configurations:\n"
            "    single_user_name: '{{ var.value.databricks_single_user_name }}'\n"
            "    data_security_mode: SINGLE_USER\n"
            "    spark_conf:\n"
            "      spark.databricks.sql.initial.catalog.namespace: "
            "quintoandar_{{ var.value.environment }}\n",
            encoding="utf-8",
        )
        (dag_dir / "enrich_semrush_classified_declaration.yml").write_text(
            "dag:\n  name: enrich_semrush_classified\n"
            "workflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )

        rec = _Rec(
            dag_id="bietlejuice.enrich_semrush_classified",
            cohort="collapse_to_single",
            confidence="high",
            actions="collapse_to_single",
            current_preset="consolidation_xs_general_single_node_cluster",
            recommended_preset="consolidation_xs_memory_single_node_cluster",
            rec_driver_node_type="r6g.large",
            rec_worker_count=0,
        )

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert cfg is not None
        cluster = cfg["validation"]["cluster"]
        assert cluster["type"] == "consolidation_xs_memory_single_node_cluster"
        assert cluster["databricks_conn_id"] == "databricks_new_env"
        custom = cluster.get("custom_configurations", {})
        assert "num_workers" not in custom
        assert "node_type_id" not in custom
        assert "driver_node_type_id" not in custom
        assert custom == {}

    def test_larger_single_node_driver_override_only(self, tmp_path):
        dag_dir = tmp_path / "dags" / "for_sale" / "ebdb_visit_fast_lane"
        dag_dir.mkdir(parents=True)
        (dag_dir / "ebdb_visit_fast_lane_cluster.yml").write_text(
            "cluster:\n  type: consolidation_m_memory_cluster\n"
            "  databricks_conn_id: databricks_new\n",
            encoding="utf-8",
        )
        (dag_dir / "ebdb_visit_fast_lane_declaration.yml").write_text(
            "dag:\n  name: ebdb_visit_fast_lane\n"
            "workflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )

        rec = _Rec(
            dag_id="bietlejuice.ebdb_visit_fast_lane",
            cohort="collapse_to_single",
            confidence="high",
            actions="collapse_to_single",
            current_preset="consolidation_m_memory_cluster",
            recommended_preset="consolidation_m_memory_single_node_cluster",
            rec_driver_node_type="r6g.4xlarge",
            driver_override_node_type_id="r6g.4xlarge",
            rec_worker_count=0,
        )

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert cfg is not None
        custom = cfg["validation"]["cluster"].get("custom_configurations", {})
        assert custom == {"driver_node_type_id": "r6g.4xlarge"}

    def test_skips_emr_prod_cluster(self, tmp_path):
        dag_dir = tmp_path / "dags" / "platform" / "dw_analytical_costs"
        dag_dir.mkdir(parents=True)
        (dag_dir / "dw_analytical_costs_cluster.yml").write_text(
            "cluster:\n"
            "  type: emr_7_12_consolidation_m_memory_cluster\n"
            "  custom_configurations:\n"
            "    core_nodes:\n"
            "      instance_count: 1\n",
            encoding="utf-8",
        )
        (dag_dir / "dw_analytical_costs_declaration.yml").write_text(
            "dag:\n  name: dw_analytical_costs\n"
            "workflow:\n  type: query_delta\n  layer: dw\n",
            encoding="utf-8",
        )

        rec = _Rec(
            dag_id="bietlejuice.dw_analytical_costs",
            cohort="collapse_to_single",
            confidence="high",
            actions="collapse_to_single",
            current_preset="emr_7_12_consolidation_m_memory_cluster",
            recommended_preset="consolidation_s_general_cluster",
            rec_driver_node_type="r6g.2xlarge",
            rec_worker_node_type="m6g.xlarge",
        )

        assert generate_validation_config(rec, dags_root=tmp_path / "dags") is None

    def test_healthy_single_drop_nvme_same_preset_emits_validation(self, tmp_path):
        dag_dir = tmp_path / "dags" / "platform" / "nvme_dag"
        dag_dir.mkdir(parents=True)
        (dag_dir / "nvme_dag_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_m_general_single_node_cluster\n"
            "  databricks_conn_id: databricks_new\n"
            "  custom_configurations:\n"
            "    driver_node_type_id: m6gd.2xlarge\n",
            encoding="utf-8",
        )
        (dag_dir / "nvme_dag_declaration.yml").write_text(
            "dag:\n  name: nvme_dag\nworkflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )

        rec = _Rec(
            dag_id="bietlejuice.nvme_dag",
            cohort="healthy_single",
            confidence="high",
            actions="drop_nvme",
            current_preset="consolidation_m_general_single_node_cluster",
            recommended_preset="consolidation_m_general_single_node_cluster",
            rec_driver_node_type="m6g.2xlarge",
            driver_override_node_type_id="m6g.2xlarge",
            rec_worker_count=0,
        )

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert cfg is not None
        assert cfg["validation"]["cluster"]["type"] == (
            "consolidation_m_general_single_node_cluster"
        )

    def test_emits_allow_custom_spark_job(self, tmp_path):
        dag_dir = tmp_path / "dags" / "growth" / "hubspot"
        dag_dir.mkdir(parents=True)
        (dag_dir / "hubspot_declaration.yml").write_text(
            "dag:\n  name: hubspot\n"
            "workflow:\n  type: query_delta\n  layer: raw\n"
            "  load_spark_job: load_hubspot_raw\n",
            encoding="utf-8",
        )
        (dag_dir / "hubspot_cluster.yml").write_text(
            "cluster:\n  type: consolidation_s_memory_single_node_cluster\n",
            encoding="utf-8",
        )

        rec = _Rec(
            dag_id="bietlejuice.hubspot",
            cohort="collapse_to_single",
            confidence="high",
            actions="collapse_to_single",
            current_preset="consolidation_s_memory_single_node_cluster",
            recommended_preset="consolidation_m_memory_single_node_cluster",
        )

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert cfg is not None
        assert cfg["validation"]["allow_custom_spark_job"] is True
        assert "custom_libraries" not in cfg["validation"]["cluster"]


class TestWriteValidationClusterFile:
    def test_remove_validation_section(self, tmp_path):
        path = tmp_path / "test_cluster.yml"
        path.write_text(
            "cluster:\n  type: emr_7_12_consolidation_m_memory_cluster\n"
            "validation:\n  cluster:\n    type: consolidation_s_general_cluster\n",
            encoding="utf-8",
        )

        assert remove_validation_from_cluster_file(path) is True
        text = path.read_text()
        assert "validation:" not in text
        assert "emr_7_12_consolidation_m_memory_cluster" in text

    def test_preserves_prod_cluster_block(self, tmp_path):
        path = tmp_path / "test_cluster.yml"
        path.write_text(
            "cluster:\n  type: old_cluster_type\n  databricks_conn_id: databricks_new_env\n",
            encoding="utf-8",
        )
        cfg = {
            "validation": {
                "cluster": {
                    "type": "consolidation_xs_memory_single_node_cluster",
                    "databricks_conn_id": "databricks_new_env",
                }
            }
        }

        write_validation_cluster_file(path, cfg, current_cluster_type=None)

        text = path.read_text()
        assert "type: old_cluster_type" in text
        assert "databricks_conn_id: databricks_new_env" in text
        assert "validation:" in text
        assert "consolidation_xs_memory_single_node_cluster" in text
