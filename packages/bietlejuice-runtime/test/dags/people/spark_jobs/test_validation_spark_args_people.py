"""Argparse smoke tests for people custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/people/currency/spark_jobs/load_currency_raw.py",
    "dags/people/degreed/spark_jobs/load_degreed_raw.py",
    "dags/people/enrich_hr_system_custom/spark_jobs/load_management_hierarchy_enrich.py",
    "dags/people/greenhouse_audit_log/spark_jobs/load_greenhouse_audit_log_raw.py",
    "dags/people/greenhouse_v3/spark_jobs/load_greenhouse_v3_raw.py",
    "dags/people/hr_system/spark_jobs/load_hr_system_raw.py",
    "dags/people/pin_absence/spark_jobs/load_pin_absence_raw.py",
    "dags/people/pin_compensation/spark_jobs/load_pin_compensation_raw.py",
    "dags/people/pin_core/spark_jobs/load_pin_core_raw.py",
    "dags/people/pin_goal/spark_jobs/load_pin_goal_raw.py",
    "dags/people/pin_hr_review/spark_jobs/load_pin_hr_review_raw.py",
    "dags/people/pin_performance/spark_jobs/load_pin_performance_raw.py",
    "dags/people/pin_questionnaires/spark_jobs/load_pin_questionnaires_raw.py",
    "dags/people/pin_talent/spark_jobs/load_pin_talent_raw.py",
    "dags/people/reverse_reports/spark_jobs/load_to_gsheet.py",
]

_JOBS_WITH_RESOLVE_CALL = {
    "dags/people/currency/spark_jobs/load_currency_raw.py",
    "dags/people/enrich_hr_system_custom/spark_jobs/load_management_hierarchy_enrich.py",
    "dags/people/hr_system/spark_jobs/load_hr_system_raw.py",
    "dags/people/reverse_reports/spark_jobs/load_to_gsheet.py",
}

_JOBS_DELEGATING_TO_LIBRARY = {
    "dags/people/degreed/spark_jobs/load_degreed_raw.py",
    "dags/people/greenhouse_audit_log/spark_jobs/load_greenhouse_audit_log_raw.py",
    "dags/people/greenhouse_v3/spark_jobs/load_greenhouse_v3_raw.py",
    "dags/people/pin_absence/spark_jobs/load_pin_absence_raw.py",
    "dags/people/pin_compensation/spark_jobs/load_pin_compensation_raw.py",
    "dags/people/pin_core/spark_jobs/load_pin_core_raw.py",
    "dags/people/pin_goal/spark_jobs/load_pin_goal_raw.py",
    "dags/people/pin_hr_review/spark_jobs/load_pin_hr_review_raw.py",
    "dags/people/pin_performance/spark_jobs/load_pin_performance_raw.py",
    "dags/people/pin_questionnaires/spark_jobs/load_pin_questionnaires_raw.py",
    "dags/people/pin_talent/spark_jobs/load_pin_talent_raw.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert (
        "add_validation_target_args" in text
        or "--target-database-name" in text
        or "OICPipeline" in text
        or "RawLayerLoader" in text
        or "BaseJobArgumentParser" in text
    )
    if job_path in _JOBS_WITH_RESOLVE_CALL:
        assert "resolve_datalake_write_target(" in text
    elif job_path in _JOBS_DELEGATING_TO_LIBRARY:
        assert "RawLayerLoader" in text or "OICPipeline" in text
