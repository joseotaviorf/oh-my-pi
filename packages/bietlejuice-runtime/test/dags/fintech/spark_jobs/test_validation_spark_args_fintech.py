"""Argparse smoke tests for fintech custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/fintech/arquivo_confidencial_integration_report/spark_jobs/load_incremental_arquivo_confidencial_raw.py",
    "dags/fintech/collections_score_batch_inference/spark_jobs/load_parquet_into_datalake.py",
    "dags/fintech/cyber/spark_jobs/load_cyber_raw.py",
    "dags/fintech/cyber_audit_log/spark_jobs/load_cyber_audit_log_raw.py",
    "dags/fintech/cyber_bureau/spark_jobs/load_cyber_raw.py",
    "dags/fintech/cyber_complement/spark_jobs/load_cyber_raw.py",
    "dags/fintech/cyber_historical_tree/spark_jobs/load_cyber_historical_tree_raw.py",
    "dags/fintech/cyber_legal/spark_jobs/load_cyber_raw.py",
    "dags/fintech/cyber_legal_historical/spark_jobs/load_cyber_raw.py",
    "dags/fintech/google_calendar/spark_jobs/load_google_calendar.py",
    "dags/fintech/grb/spark_jobs/load_grb_raw.py",
    "dags/fintech/invoice_preview/spark_jobs/load_csv_into_datalake.py",
    "dags/fintech/itau_statements/spark_jobs/load_raw.py",
    "dags/fintech/meetcall/spark_jobs/load_meetcall_raw.py",
    "dags/fintech/nexxera/spark_jobs/load_csv_into_datalake.py",
    "dags/fintech/payable_accounts_transactions/spark_jobs/load_sheets_into_datalake.py",
    "dags/fintech/sap_4hana/spark_jobs/load_raw.py",
    "dags/fintech/velo_zendesk/spark_jobs/add_partitions_to_raw_tables.py",
]


_JOBS_WITHOUT_WRITE_TARGET = {
    "dags/fintech/velo_zendesk/spark_jobs/add_partitions_to_raw_tables.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _JOBS_WITHOUT_WRITE_TARGET:
        assert "is_validation_run" in text
    else:
        assert "resolve_datalake_write_target(" in text


def test_nexxera_uses_dual_runtime_spark_client():
    job_path = _REPO_ROOT / "dags/fintech/nexxera/spark_jobs/load_csv_into_datalake.py"
    text = job_path.read_text(encoding="utf-8")

    assert "SparkClient(app_name=JOB_NAME)" in text
    assert "spark = spark_client.conn" in text
    assert "from bietlejuice.base.spark import" not in text
