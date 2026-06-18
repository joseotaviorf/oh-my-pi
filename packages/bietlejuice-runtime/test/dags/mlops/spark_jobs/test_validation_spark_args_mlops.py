"""Argparse smoke tests for mlops custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/mlops/batch_inference/spark_jobs/load_parquet_into_datalake.py",
    "dags/mlops/emlio/spark_jobs/load_emlio_raw.py",
    "dags/mlops/evidently_ml_monitor/spark_jobs/load_evidently_ml_monitor_raw.py",
]


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    assert "resolve_datalake_write_target(" in text
