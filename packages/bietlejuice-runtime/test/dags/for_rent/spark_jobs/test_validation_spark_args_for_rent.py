"""Argparse smoke tests for for_rent custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/for_rent/offboarding_categorization/spark_jobs/load_offboarding_categorization_raw.py",
    "dags/for_rent/vocs_machina/spark_jobs/load_vocs_machina_raw.py",
]


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    assert "resolve_datalake_write_target(" in text
