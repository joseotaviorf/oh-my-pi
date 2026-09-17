"""Argparse smoke tests for agents custom Spark jobs (cluster validation flags)."""

from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[6]

_JOB_PATHS = [
    "dags/agents/airtable/spark_jobs/load_airtable_raw.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_status_by_month.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_independent_campinas_metrics.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_new_agent_activation_metrics.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_new_agent_activation_daily.py",
    "dags/agents/enrich_amplitude_agents_app/spark_jobs/load_buyer_funnel_users.py",
    "dags/agents/enrich_planner_emlio_logs/spark_jobs/load_planner_emlio_logs.py",
    "dags/agents/enrich_agents_matias/spark_jobs/load_eval_session_bundle.py",
    "dags/agents/enrich_agents_matias/spark_jobs/load_matias_session_summary.py",
    "dags/agents/enrich_agents_matias/spark_jobs/load_matias_sessions_html_format.py",
    "dags/agents/dw_agent_visit_funnel/spark_jobs/load_agent_visit_funnel.py",
]

_JOBS_WITH_RESOLVE = {
    "dags/agents/airtable/spark_jobs/load_airtable_raw.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_status_by_month.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_independent_campinas_metrics.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_new_agent_activation_metrics.py",
    "dags/agents/enrich_agent_reports/spark_jobs/load_agent_new_agent_activation_daily.py",
    "dags/agents/enrich_amplitude_agents_app/spark_jobs/load_buyer_funnel_users.py",
    "dags/agents/enrich_planner_emlio_logs/spark_jobs/load_planner_emlio_logs.py",
    "dags/agents/enrich_agents_matias/spark_jobs/load_eval_session_bundle.py",
    "dags/agents/enrich_agents_matias/spark_jobs/load_matias_session_summary.py",
    "dags/agents/enrich_agents_matias/spark_jobs/load_matias_sessions_html_format.py",
    "dags/agents/dw_agent_visit_funnel/spark_jobs/load_agent_visit_funnel.py",
}


@pytest.mark.parametrize("job_path", _JOB_PATHS)
def test_spark_job_registers_validation_write_flags(job_path: str):
    text = (_REPO_ROOT / job_path).read_text(encoding="utf-8")
    assert "add_validation_target_args" in text or "--target-database-name" in text
    if job_path in _JOBS_WITH_RESOLVE:
        assert "resolve_datalake_write_target(" in text
