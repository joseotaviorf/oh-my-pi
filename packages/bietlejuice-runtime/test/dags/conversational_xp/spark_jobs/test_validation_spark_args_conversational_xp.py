"""Argparse smoke tests for conversational_xp custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/conversational_xp/conversation_explorer/spark_jobs/load_conversation_explorer.py",
    "dags/conversational_xp/langfuse/spark_jobs/fetch_data.py",
    "dags/conversational_xp/reverse_minority_report_ss/spark_jobs/load_reverse_minority_report_ss.py",
    "dags/conversational_xp/text2filter_evals/spark_jobs/load_text2filter_evals_into_datalake.py",
]

_JOBS_WITH_RESOLVE = {
    "dags/conversational_xp/conversation_explorer/spark_jobs/load_conversation_explorer.py",
    "dags/conversational_xp/langfuse/spark_jobs/fetch_data.py",
    "dags/conversational_xp/text2filter_evals/spark_jobs/load_text2filter_evals_into_datalake.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _JOBS_WITH_RESOLVE:
        assert "resolve_datalake_write_target(" in text
