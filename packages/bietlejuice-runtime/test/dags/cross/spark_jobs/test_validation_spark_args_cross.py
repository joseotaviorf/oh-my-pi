"""Argparse smoke tests for cross custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/cross/base/spark_jobs/load_mongo_raw.py",
    "dags/cross/base/spark_jobs/load_growth_intel_crawler_raw.py",
    "dags/cross/kong/spark_jobs/load_kong_raw.py",
    "dags/cross/request_logging/spark_jobs/fetch_data.py",
    "dags/cross/reverse_birdie_access/spark_jobs/load_into_birdie_api.py",
]

_JOBS_WITH_RESOLVE = {
    "dags/cross/base/spark_jobs/load_mongo_raw.py",
    "dags/cross/base/spark_jobs/load_growth_intel_crawler_raw.py",
    "dags/cross/kong/spark_jobs/load_kong_raw.py",
    "dags/cross/request_logging/spark_jobs/fetch_data.py",
    "dags/cross/reverse_birdie_access/spark_jobs/load_into_birdie_api.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _JOBS_WITH_RESOLVE:
        assert "resolve_datalake_write_target(" in text
