"""Argparse smoke tests for for_sale custom Spark jobs (cluster validation flags)."""

import re
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/for_sale/reverse_idactum_access/spark_jobs/load_s3_data_into_external_bucket.py",
]


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    assert (
        "resolve_datalake_write_target" in text or "resolve_validation_target" in text
    )


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_validation_reads_per_table(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "resolve_validation_target(prod_database, table)" in text
    assert "validation_database_location" in text
    assert "args.target_database_name" in text
    loop_match = re.search(
        r"for table in tables:.*?(?=\n    [a-z_]|\n\n|\Z)",
        text,
        flags=re.DOTALL,
    )
    assert loop_match is not None
    loop_block = loop_match.group(0)
    assert "args.target_table_name" not in loop_block, (
        f"{job_path} must not pass a fixed validation table inside the per-table loop"
    )
