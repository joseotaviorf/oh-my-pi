"""Unit tests for rightsizing_validation_config."""

from __future__ import annotations

from dataclasses import dataclass, field

from scripts.ci_cd.airflow_dag_builder.rightsizing_validation_config import (
    generate_validation_config,
    remove_validation_from_cluster_file,
    write_validation_cluster_file,
    write_validation_configs,
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
    def test_skips_when_recommendation_resolves_to_prod_spec(self):
        # Same preset, no overrides: rec collapses to prod's exact effective spec.
        rec = _Rec(
            dag_id="bietlejuice.test_dag",
            cohort="collapse_to_single",
            confidence="high",
            actions="collapse_to_single",
            current_preset="consolidation_m_memory_single_node_cluster",
            recommended_preset="consolidation_m_memory_single_node_cluster",
            rec_worker_count=0,
        )

        assert generate_validation_config(rec) is None

    def test_keeps_same_preset_driver_only_downsize(self):
        # Same preset but a driver override resolves to a smaller driver than the
        # preset default (r6g.2xlarge -> r6g.xlarge): a real validation, not a no-op.
        rec = _Rec(
            dag_id="bietlejuice.test_dag",
            cohort="driver_downsize",
            confidence="high",
            actions="reduce_driver",
            current_preset="consolidation_m_memory_cluster",
            recommended_preset="consolidation_m_memory_cluster",
            driver_override_node_type_id="r6g.xlarge",
            rec_driver_node_type="r6g.xlarge",
        )

        cfg = generate_validation_config(rec)
        assert cfg is not None
        assert (
            cfg["validation"]["cluster"]["custom_configurations"]["driver_node_type_id"]
            == "r6g.xlarge"
        )

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

    def test_multi_node_rec_strips_inherited_single_node_settings(self, tmp_path):
        """Regression: prod on a single-node preset must not bleed singleNode spark_conf
        into validation when the recommendation targets a multi-node preset."""
        dag_dir = tmp_path / "dags" / "fintech" / "dw_collections_landlord"
        dag_dir.mkdir(parents=True)
        (dag_dir / "dw_collections_landlord_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_xl_general_single_node_cluster\n"
            "  databricks_conn_id: databricks_new_env\n"
            "  custom_configurations:\n"
            "    driver_node_type_id: m6g.12xlarge\n"
            "    spark_version: 16.4.x-scala2.12\n"
            "    num_workers: 4\n",
            encoding="utf-8",
        )
        (dag_dir / "dw_collections_landlord_declaration.yml").write_text(
            "dag:\n  name: dw_collections_landlord\n"
            "workflow:\n  type: query_delta\n  layer: dw\n",
            encoding="utf-8",
        )

        rec = _Rec(
            dag_id="bietlejuice.dw_collections_landlord",
            cohort="right_size_multi",
            confidence="high",
            actions="keep_multi_node|reduce_driver|keep_worker_type|keep_worker_count",
            current_preset="consolidation_xl_general_single_node_cluster",
            current_driver_node_type="m6g.12xlarge",
            current_worker_node_type="m6g.12xlarge",
            current_worker_count=4,
            recommended_preset="consolidation_m_general_cluster",
            rec_driver_node_type="r6g.xlarge",
            rec_worker_node_type="m6g.2xlarge",
            rec_worker_count=4,
            num_workers_override=4,
            driver_override_node_type_id="r6g.xlarge",
        )

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert cfg is not None
        cluster = cfg["validation"]["cluster"]
        assert cluster["type"] == "consolidation_m_general_cluster"
        custom = cluster.get("custom_configurations", {})
        spark_conf = custom.get("spark_conf", {})
        assert "spark.databricks.cluster.profile" not in spark_conf
        assert "spark.master" not in spark_conf
        custom_tags = custom.get("custom_tags", {})
        assert custom_tags.get("ResourceClass") != "SingleNode"
        assert "ResourceClass" not in custom_tags

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

    def test_retarget_generation_emits_gen7_overrides(self, tmp_path):
        dag_dir = tmp_path / "dags" / "platform" / "gen_dag"
        dag_dir.mkdir(parents=True)
        (dag_dir / "gen_dag_cluster.yml").write_text(
            "cluster:\n"
            "  type: consolidation_m_general_cluster\n"
            "  databricks_conn_id: databricks_new\n"
            "  custom_configurations:\n"
            "    driver_node_type_id: m6g.2xlarge\n"
            "    node_type_id: m6g.2xlarge\n",
            encoding="utf-8",
        )
        (dag_dir / "gen_dag_declaration.yml").write_text(
            "dag:\n  name: gen_dag\nworkflow:\n  type: query_delta\n  layer: enrich\n",
            encoding="utf-8",
        )

        rec = _Rec(
            dag_id="bietlejuice.gen_dag",
            cohort="keep_multi_cost",
            confidence="high",
            actions="retarget_generation",
            current_preset="consolidation_m_general_cluster",
            recommended_preset="consolidation_m_general_cluster",
            rec_driver_node_type="m7g.xlarge",
            rec_worker_node_type="m7g.2xlarge",
            rec_worker_count=2,
            driver_override_node_type_id="m7g.xlarge",
        )

        cfg = generate_validation_config(rec, dags_root=tmp_path / "dags")

        assert cfg is not None
        custom = cfg["validation"]["cluster"]["custom_configurations"]
        assert custom["driver_node_type_id"] == "m7g.xlarge"
        assert custom["node_type_id"] == "m7g.2xlarge"


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


NOOP_CLUSTER_BODY = "cluster:\n  type: consolidation_xs_memory_cluster\n  custom_configurations:\n    num_workers: 3\n    driver_node_type_id: r6g.xlarge\nvalidation:\n  cluster:\n    type: consolidation_xs_memory_cluster\n    custom_configurations:\n      num_workers: 3\n      driver_node_type_id: r6g.xlarge\n"
REAL_CLUSTER_BODY = "cluster:\n  type: consolidation_xs_memory_cluster\n  custom_configurations:\n    num_workers: 3\n    driver_node_type_id: m6g.xlarge\nvalidation:\n  cluster:\n    type: consolidation_xs_memory_cluster\n    custom_configurations:\n      num_workers: 3\n"


class TestWriteValidationConfigsPrune:
    """--write-cluster-files prunes only stale (resolves-to-prod) validation blocks."""

    @staticmethod
    def _write_cluster(dags_root, dag_name, body):
        dag_dir = dags_root / "growth" / dag_name
        dag_dir.mkdir(parents=True)
        cluster_path = dag_dir / f"{dag_name}_cluster.yml"
        cluster_path.write_text(body, encoding="utf-8")
        return cluster_path

    def test_prunes_stale_noop_validation_block(self, tmp_path):
        dags_root = tmp_path / "dags"
        cluster_path = self._write_cluster(dags_root, "noop_dag", NOOP_CLUSTER_BODY)
        # Non-actionable cohort -> generate_validation_config returns None, but the
        # existing block resolves to prod (stale, e.g. post-promotion) so it is pruned.
        rec = _Rec(
            dag_id="bietlejuice.noop_dag",
            cohort="no_change",
            confidence="high",
            actions="no_change",
            current_preset="consolidation_xs_memory_cluster",
        )
        write_validation_configs(
            [rec],
            tmp_path / "out.yml",
            dags_root=dags_root,
            write_cluster_files=True,
        )
        text = cluster_path.read_text(encoding="utf-8")
        assert "validation:" not in text
        assert "cluster:" in text

    def test_keeps_real_validation_block_for_non_actionable_dag(self, tmp_path):
        dags_root = tmp_path / "dags"
        cluster_path = self._write_cluster(dags_root, "active_dag", REAL_CLUSTER_BODY)
        # Non-actionable this run, but the in-progress validation does NOT resolve to
        # prod (driver downsize), so the block must be preserved.
        rec = _Rec(
            dag_id="bietlejuice.active_dag",
            cohort="no_change",
            confidence="high",
            actions="no_change",
            current_preset="consolidation_xs_memory_cluster",
        )
        write_validation_configs(
            [rec],
            tmp_path / "out.yml",
            dags_root=dags_root,
            write_cluster_files=True,
        )
        text = cluster_path.read_text(encoding="utf-8")
        assert "validation:" in text
