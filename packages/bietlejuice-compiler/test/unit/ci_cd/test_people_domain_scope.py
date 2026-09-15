"""Unit tests for people_domain_scope path helpers."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.people_domain_scope import (  # noqa: E402
    dag_folder_from_path,
    dq_path_for_artifact,
    is_scoped_domain_path,
    metadata_path_for_sql,
)


def test_is_scoped_domain_path_people():
    assert is_scoped_domain_path("dags/people/pin/queries/clean/foo.sql")


def test_is_scoped_domain_path_enterprise_efficiency():
    assert is_scoped_domain_path(
        "dags/enterprise_efficiency/claude_usage_api/queries/clean/foo.sql"
    )


def test_dag_folder_from_enterprise_efficiency_path():
    path = Path("dags/enterprise_efficiency/claude_usage_api/queries/clean/sample.sql")
    assert dag_folder_from_path(path) == "claude_usage_api"


def test_metadata_path_for_sql_enterprise_efficiency():
    sql_path = Path(
        "dags/enterprise_efficiency/dw_ai_usage/queries/dw/dim_ai_model.sql"
    )
    meta = metadata_path_for_sql(sql_path)
    assert meta == Path(
        "dags/enterprise_efficiency/dw_ai_usage/metadata/dw/dim_ai_model.yml"
    )


def test_dq_path_for_enterprise_efficiency_metadata_artifact():
    artifact = (
        "dags/enterprise_efficiency/enrich_ai_usage/metadata/enrich/usage_daily.yml"
    )
    dq_path = dq_path_for_artifact(artifact)
    assert dq_path == Path(
        "dags/enterprise_efficiency/enrich_ai_usage/data_quality/enrich/usage_daily.yml"
    )
