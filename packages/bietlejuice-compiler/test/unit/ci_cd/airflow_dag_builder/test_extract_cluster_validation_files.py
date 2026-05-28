"""Unit tests for verbatim cluster extraction."""

from __future__ import annotations

from pathlib import Path

from scripts.ci_cd.airflow_dag_builder.extract_cluster_validation_files import (
    _validate_allow_custom_spark_job_contract,
    build_cluster_file_content,
    extract_cluster_section_text,
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
