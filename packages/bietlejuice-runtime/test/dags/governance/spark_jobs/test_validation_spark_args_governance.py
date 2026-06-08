"""Argparse smoke tests for governance custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/governance/enrich_anonymization/spark_jobs/load_columns_sample_data.py",
    "dags/governance/enrich_anonymization/spark_jobs/load_pii_scan_into_datalake.py",
    "dags/governance/enrich_datahub_assets/spark_jobs/load_datahub_assets.py",
    "dags/governance/enrich_fairness_assessment/spark_jobs/load_fairness_assessment.py",
    "dags/governance/enrich_jira/spark_jobs/load_deleted_issues.py",
    "dags/governance/inmetro/spark_jobs/load_inmetro_raw.py",
    "dags/governance/jira/spark_jobs/load_full_data_into_datalake_raw.py",
    "dags/governance/jira/spark_jobs/load_incremental_data_into_datalake_raw.py",
    "dags/governance/jira_ops/spark_jobs/load_jira_ops_data_into_datalake_raw.py",
    "dags/governance/jira_ops/spark_jobs/load_responders_account_into_datalake_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_categories_documentation_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_columns_documentation_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_columns_metastore_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_dag_metadata_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_lineage_and_tags_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_tables_documentation_to_raw.py",
    "dags/governance/metabase_pull/spark_jobs/load_incremental_data_into_datalake_raw.py",
    "dags/governance/metrics_governance/spark_jobs/load_metrics_registration_into_raw.py",
    "dags/governance/reverse_anonymization/spark_jobs/load_results_into_gsheet.py",
    "dags/governance/reverse_dashboard_governance/spark_jobs/load_dashboard_governance_into_mp.py",
    "dags/governance/reverse_dashboard_governance/spark_jobs/load_data_assets_into_mp.py",
]

_JOBS_WITH_RESOLVE = {
    "dags/governance/enrich_anonymization/spark_jobs/load_columns_sample_data.py",
    "dags/governance/enrich_anonymization/spark_jobs/load_pii_scan_into_datalake.py",
    "dags/governance/enrich_datahub_assets/spark_jobs/load_datahub_assets.py",
    "dags/governance/enrich_fairness_assessment/spark_jobs/load_fairness_assessment.py",
    "dags/governance/enrich_jira/spark_jobs/load_deleted_issues.py",
    "dags/governance/inmetro/spark_jobs/load_inmetro_raw.py",
    "dags/governance/jira/spark_jobs/load_full_data_into_datalake_raw.py",
    "dags/governance/jira/spark_jobs/load_incremental_data_into_datalake_raw.py",
    "dags/governance/jira_ops/spark_jobs/load_jira_ops_data_into_datalake_raw.py",
    "dags/governance/jira_ops/spark_jobs/load_responders_account_into_datalake_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_categories_documentation_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_columns_documentation_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_columns_metastore_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_dag_metadata_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_lineage_and_tags_to_raw.py",
    "dags/governance/documentation_metrics/spark_jobs/load_tables_documentation_to_raw.py",
    "dags/governance/metabase_pull/spark_jobs/load_incremental_data_into_datalake_raw.py",
    "dags/governance/metrics_governance/spark_jobs/load_metrics_registration_into_raw.py",
    "dags/governance/reverse_anonymization/spark_jobs/load_results_into_gsheet.py",
    "dags/governance/reverse_dashboard_governance/spark_jobs/load_dashboard_governance_into_mp.py",
    "dags/governance/reverse_dashboard_governance/spark_jobs/load_data_assets_into_mp.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _JOBS_WITH_RESOLVE:
        assert "resolve_datalake_write_target(" in text
