"""Unit tests for verbatim cluster extraction."""

from __future__ import annotations

import sys
from pathlib import Path

import yaml

from scripts.ci_cd.airflow_dag_builder.extract_cluster_validation_files import (
    _validate_allow_custom_spark_job_contract,
    _validate_cluster_file_yaml_format,
    build_cluster_file_content,
    extract_cluster_section_text,
    extract_validation_section_text,
    main,
    process_cluster_file,
    remove_cluster_section_text,
)

pytest_plugins = ["test.unit.ci_cd.airflow_dag_builder.cluster_validation_prod_env"]

SAMPLE_DECLARATION = """dag:
  name: sample_dag
workflow:
  type: query_delta
cluster:
  type: custom_cluster
  custom_configurations:
    spark_conf:
      spark.databricks.sql.initial.catalog.namespace: quintoandar_{{ var.value.environment }}
    num_workers: 1
"""

CLUSTER_WITH_CUSTOM_JOB = """cluster:
  type: databricks_16_4_med_general_cluster
  databricks_conn_id: databricks_new
"""

CLUSTER_SQL_ONLY = """cluster:
  type: databricks_16_4_small_general_fleet_8xlarge_single_node
  databricks_conn_id: databricks_new
"""


class TestExtractClusterValidationFiles:
    def test_extract_cluster_section_preserves_single_line_spark_conf(self):
        block = extract_cluster_section_text(SAMPLE_DECLARATION)
        assert block is not None
        assert "quintoandar_{{ var.value.environment }}" in block
        assert "environment\n        }}" not in block

    def test_remove_cluster_section_keeps_other_keys(self):
        updated = remove_cluster_section_text(SAMPLE_DECLARATION)
        assert "cluster:" not in updated
        assert "workflow:" in updated
        assert "dag:" in updated

    def test_build_cluster_file_content_emits_allow_custom_when_load_spark_job(self):
        declaration = {
            "dag": {"name": "test_dag"},
            "workflow": {
                "type": "query_delta",
                "layer": "enrich",
                "load_spark_job": "load_test",
            },
            "cluster": {"type": "databricks_16_4_med_general_cluster"},
        }
        cluster_args = declaration["cluster"]
        content = build_cluster_file_content(
            cluster_text=CLUSTER_WITH_CUSTOM_JOB,
            declaration=declaration,
            cluster_args=cluster_args,
        )
        assert "validation:" in content
        assert "allow_custom_spark_job: true" in content
        assert content.endswith("\n")
        assert not content.endswith("\n\n")
        assert "\n\nvalidation:" not in content

    def test_build_cluster_file_content_omits_allow_custom_without_load_spark_job(self):
        declaration = {
            "dag": {"name": "core_aux_listing"},
            "workflow": {"type": "query_delta", "layer": "core"},
            "cluster": {
                "type": "databricks_16_4_small_general_fleet_8xlarge_single_node",
            },
        }
        cluster_args = declaration["cluster"]
        content = build_cluster_file_content(
            cluster_text=CLUSTER_SQL_ONLY,
            declaration=declaration,
            cluster_args=cluster_args,
        )
        assert "validation:" in content
        assert "allow_custom_spark_job" not in content

    def test_validate_allow_custom_contract_detects_missing_flag(self):
        declaration = {
            "dag": {"name": "x"},
            "workflow": {
                "type": "query_delta",
                "layer": "enrich",
                "load_spark_job": "job",
            },
        }
        bad_content = (
            "cluster:\n  type: x\n\nvalidation:\n  cluster:\n"
            "    type: consolidation_s_general_cluster\n"
        )
        err = _validate_allow_custom_spark_job_contract(
            bad_content,
            declaration,
            context_path=Path("dags/foo/foo_cluster.yml"),
        )
        assert err is not None
        assert "missing allow_custom_spark_job" in err

    def test_validate_allow_custom_contract_detects_unexpected_flag(self):
        declaration = {
            "dag": {"name": "x"},
            "workflow": {"type": "query_delta", "layer": "core"},
        }
        bad_content = (
            "cluster:\n  type: x\n\nvalidation:\n  cluster:\n"
            "    type: consolidation_s_general_cluster\n"
            "  allow_custom_spark_job: true\n"
        )
        err = _validate_allow_custom_spark_job_contract(
            bad_content,
            declaration,
            context_path=Path("dags/foo/foo_cluster.yml"),
        )
        assert err is not None
        assert "unexpected allow_custom_spark_job" in err

    def test_validate_cluster_file_yaml_format_rejects_folded_jinja(self):
        folded = """cluster:
  custom_configurations:
    spark_conf:
      spark.databricks.sql.initial.catalog.namespace: quintoandar_{{ var.value.environment
        }}
"""
        err = _validate_cluster_file_yaml_format(
            Path("dags/foo/foo_cluster.yml"), folded
        )
        assert err is not None
        assert "folded spark.databricks" in err

    def test_validate_cluster_file_yaml_format_accepts_single_line(self):
        ok = """cluster:
  custom_configurations:
    spark_conf:
      spark.databricks.sql.initial.catalog.namespace: quintoandar_{{ var.value.environment }}
"""
        assert (
            _validate_cluster_file_yaml_format(Path("dags/foo/foo_cluster.yml"), ok)
            is None
        )

    def test_build_cluster_file_normalizes_legacy_prod_topology(self):
        declaration = {
            "dag": {"name": "legacy_dag"},
            "workflow": {"type": "query_delta", "layer": "enrich"},
            "cluster": {
                "type": "custom_cluster",
                "custom_configurations": {
                    "driver_node_type_id": "m5a.xlarge",
                    "node_type_id": "m5a.large",
                    "num_workers": 1,
                    "spark_version": "16.4.x-scala2.12",
                },
            },
        }
        cluster_args = declaration["cluster"]
        content = build_cluster_file_content(
            cluster_text="cluster:\n  type: custom_cluster\n",
            declaration=declaration,
            cluster_args=cluster_args,
        )
        assert "driver_node_type_id: m6g.xlarge" in content
        assert "node_type_id: m6g.large" in content
        assert "m5a." not in content
        assert "validation:" in content
        document = yaml.safe_load(content)
        validation_custom = (
            document.get("validation", {})
            .get("cluster", {})
            .get("custom_configurations", {})
        )
        assert "node_type_id" not in validation_custom

    def test_build_cluster_file_preserves_verbatim_emr_block_with_comments(self):
        cluster_text = """cluster:
  type: emr_7_12_consolidation_s_general_cluster
  custom_configurations:
    # Cost-saving spot/OD mix: 1 CORE on-demand + 2 TASK spot (~67% spot).
    core_nodes:
        instance_count: 1
    task_nodes:
        instance_count: 2
    spark_conf:
      spark.driver.memory: 8g
"""
        declaration = {
            "dag": {"name": "dw_agent"},
            "workflow": {"type": "query_delta", "layer": "dw"},
            "cluster": yaml.safe_load(cluster_text)["cluster"],
        }
        content = build_cluster_file_content(
            cluster_text=cluster_text,
            declaration=declaration,
            cluster_args=declaration["cluster"],
        )
        assert "# Cost-saving spot/OD mix" in content
        assert "task_nodes:\n        instance_count: 2" in content
        assert "validation:" not in content

    def test_process_cluster_file_preserves_validation_section_verbatim(self, tmp_path):
        dag_dir = tmp_path / "rightsized_dag"
        dag_dir.mkdir()
        declaration_path = dag_dir / "rightsized_dag_declaration.yml"
        declaration_path.write_text(
            "dag:\n"
            "  name: rightsized_dag\n"
            "workflow:\n"
            "  type: query_delta\n"
            "  layer: enrich\n",
            encoding="utf-8",
        )
        cluster_path = dag_dir / "rightsized_dag_cluster.yml"
        on_disk = (
            "cluster:\n"
            "  type: consolidation_m_general_cluster\n"
            "  custom_libraries:\n"
            "    - pypi:\n"
            "        package: foo\n"
            "validation:\n"
            "  cluster:\n"
            "    type: consolidation_s_general_cluster\n"
            "    databricks_conn_id: databricks_new\n"
            "    custom_configurations:\n"
            "      driver_node_type_id: r6g.xlarge\n"
        )
        cluster_path.write_text(on_disk, encoding="utf-8")

        _, content = process_cluster_file(cluster_path)

        assert content is not None
        assert extract_validation_section_text(
            content
        ) == extract_validation_section_text(on_disk)
        document = yaml.safe_load(content)
        assert "custom_libraries" not in document["validation"]["cluster"]

    def test_check_mode_accepts_minimal_validation_stage_block(
        self, tmp_path, monkeypatch
    ):
        dag_dir = tmp_path / "ebdb_location"
        dag_dir.mkdir()
        declaration_path = dag_dir / "ebdb_location_declaration.yml"
        declaration_path.write_text(
            "dag:\n"
            "  name: ebdb_location\n"
            "workflow:\n"
            "  type: query_delta\n"
            "  layer: enrich\n",
            encoding="utf-8",
        )
        cluster_path = dag_dir / "ebdb_location_cluster.yml"
        cluster_path.write_text(
            "cluster:\n"
            "  type: custom_cluster_with_sedona\n"
            "  custom_configurations:\n"
            "    driver_node_type_id: m6g.xlarge\n"
            "    node_type_id: m6g.xlarge\n"
            "    num_workers: 3\n"
            "    spark_version: 16.4.x-scala2.12\n"
            "validation:\n"
            "  cluster:\n"
            "    type: consolidation_s_general_cluster\n"
            "    custom_configurations:\n"
            "      num_workers: 3\n",
            encoding="utf-8",
        )
        monkeypatch.setattr(
            sys,
            "argv",
            ["extract_cluster_validation_files.py", str(tmp_path), "--check"],
        )

        assert main() == 0
