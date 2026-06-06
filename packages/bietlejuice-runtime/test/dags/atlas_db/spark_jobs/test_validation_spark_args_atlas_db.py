"""Argparse smoke tests for atlas_db custom Spark jobs (cluster validation flags)."""

import re
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/atlas_db/clustering_image_model/spark_jobs/load_clustering_image_model_raw.py",
    "dags/atlas_db/iptu_bh/spark_jobs/load_iptu_bh_raw.py",
    "dags/atlas_db/iptu_poa/spark_jobs/load_iptu_poa_raw.py",
    "dags/atlas_db/iptu_sp/spark_jobs/load_iptu_sp_raw.py",
    "dags/atlas_db/itbi_bh/spark_jobs/load_itbi_bh_raw.py",
    "dags/atlas_db/itbi_sp/spark_jobs/load_itbi_sp_raw.py",
]


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    # Arrange
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")

    # Act & Assert
    assert "add_validation_target_args" in text or "--target-database-name" in text
    assert "resolve_datalake_write_target(" in text


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_resolve_uses_validation_target_args(job_path: str):
    # Arrange
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")

    # Act & Assert
    for block in re.findall(
        r"resolve_datalake_write_target\((.*?)\)", text, flags=re.DOTALL
    ):
        uses_bare_target_name = (
            "target_database=target_database_name" in block
            or "target_table=target_table_name" in block
        )
        uses_args_targets = "target_database=args.target_database_name" in block or (
            "target_database=target_database_name," in block
            and "parse_arguments()" in text
        )
        assert not uses_bare_target_name or uses_args_targets, (
            f"{job_path} passes unresolved target_database_name/target_table_name "
            "into resolve_datalake_write_target"
        )
