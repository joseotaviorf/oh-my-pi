"""Argparse smoke tests for house_and_listing custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/house_and_listing/dw_pricing/spark_jobs/load_dim_pricing.py",
    "dags/house_and_listing/dw_pricing/spark_jobs/load_dim_price_suggested.py",
    "dags/house_and_listing/dw_pricing/spark_jobs/load_fact_price_changes.py",
    "dags/house_and_listing/dw_pricing/spark_jobs/load_fact_price_suggested.py",
    "dags/house_and_listing/enrich_ebdb_pricing/spark_jobs/load_house_suggestion_changes.py",
    "dags/house_and_listing/enrich_ebdb_pricing/spark_jobs/load_listing_price_change.py",
    "dags/house_and_listing/reverse_sale_unavailable_listings_access/spark_jobs/load_into_s3.py",
]

_REVERSE_EXPORT_JOBS = {
    "dags/house_and_listing/reverse_sale_unavailable_listings_access/spark_jobs/load_into_s3.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _REVERSE_EXPORT_JOBS:
        assert "is_validation_run" in text
    else:
        assert "resolve_datalake_write_target(" in text
