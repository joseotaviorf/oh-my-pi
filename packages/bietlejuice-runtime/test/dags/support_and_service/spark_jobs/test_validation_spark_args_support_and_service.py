"""Argparse smoke tests for support_and_service custom Spark jobs (cluster validation flags)."""

import re
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/support_and_service/braze_analytics/spark_jobs/load_braze_analytics_raw.py",
    "dags/support_and_service/braze_details/spark_jobs/load_braze_details_raw.py",
    "dags/support_and_service/braze_events/spark_jobs/load_braze_events_raw.py",
    "dags/support_and_service/comms_manager_rules/spark_jobs/load_comms_manager_rules.py",
    "dags/support_and_service/internal_chat/spark_jobs/load_internal_chat_raw.py",
    "dags/support_and_service/reclameaqui/spark_jobs/load_reclameaqui_tickets.py",
    "dags/support_and_service/reverse_tracksale_access/spark_jobs/load_targets_into_tracksale.py",
    "dags/support_and_service/reverse_webhelp_access/spark_jobs/load_into_azure_blob_storage.py",
    "dags/support_and_service/salesforce/spark_jobs/load_salesforce_raw.py",
    "dags/support_and_service/survicate_respondent_attributes/spark_jobs/load_survicate_respondent_attributes_raw.py",
    "dags/support_and_service/survicate_survey_attributes/spark_jobs/load_survicate_survey_attributes_raw.py",
    "dags/support_and_service/survicate_surveys/spark_jobs/load_survicate_surveys_raw.py",
    "dags/support_and_service/twilio_flex_insights/spark_jobs/load_twilio_flex_insights_raw.py",
    "dags/support_and_service/tracksale/spark_jobs/load_full_data_into_datalake_raw.py",
    "dags/support_and_service/tracksale/spark_jobs/load_incremental_data_into_datalake_raw.py",
    "dags/support_and_service/zendesk/spark_jobs/add_data_from_airbyte_to_raw.py",
    "dags/support_and_service/zendesk/spark_jobs/add_data_from_stitch_to_raw.py",
]


_REVERSE_EXPORT_JOBS = {
    "dags/support_and_service/reverse_tracksale_access/spark_jobs/load_targets_into_tracksale.py",
    "dags/support_and_service/reverse_webhelp_access/spark_jobs/load_into_azure_blob_storage.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _REVERSE_EXPORT_JOBS:
        assert "is_validation_run" in text
    else:
        assert "resolve_datalake_write_target" in text


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_resolve_uses_validation_target_args(job_path: str):
    if job_path in _REVERSE_EXPORT_JOBS:
        pytest.skip("reverse export jobs do not resolve datalake write targets")
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    for block in re.findall(
        r"resolve_datalake_write_target\((.*?)\)", text, flags=re.DOTALL
    ):
        uses_bare_target_name = (
            "target_database=target_database_name" in block
            or "target_table=target_table_name" in block
        )
        uses_args_targets = (
            "target_database=args.target_database_name" in block
            or "target_database=target_database_name," in block
            and "parse_arguments()" in text
        )
        assert not uses_bare_target_name or uses_args_targets, (
            f"{job_path} passes unresolved target_database_name/target_table_name "
            "into resolve_datalake_write_target"
        )
