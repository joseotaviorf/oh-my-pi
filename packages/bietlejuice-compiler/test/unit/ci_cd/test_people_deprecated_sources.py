"""Unit tests for people_deprecated_sources pattern matching."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.people_deprecated_sources import (  # noqa: E402
    find_deprecated_source_hits,
    is_legacy_dag_exempt,
    people_dag_folder,
)


def test_people_dag_folder_from_sql_path():
    path = Path("dags/people/pin/queries/clean/sample.sql")
    assert people_dag_folder(path) == "pin"


def test_legacy_dag_exempt_dw_employee():
    path = Path("dags/people/dw_employee/queries/dw/fact.sql")
    assert is_legacy_dag_exempt(path)


def test_non_legacy_dag_not_exempt():
    path = Path("dags/people/pin/queries/clean/sample.sql")
    assert not is_legacy_dag_exempt(path)


def test_find_hr_system_reference():
    hits = find_deprecated_source_hits(
        "SELECT id FROM datalake_hr_system_clean.employee_info"
    )
    assert hits[0][0] == "datalake_hr_system"


def test_greenhouse_v3_not_flagged():
    hits = find_deprecated_source_hits(
        "SELECT id FROM datalake_greenhouse_v3_clean.applications"
    )
    assert hits == []


def test_id_greenhouse_column_not_flagged():
    hits = find_deprecated_source_hits("SELECT id_greenhouse FROM datalake_people.base")
    assert hits == []


def test_line_comment_does_not_hide_following_line():
    sql = (
        "-- deprecated sources policy\n"
        "SELECT id FROM datalake_hr_system_clean.employee_info"
    )
    hits = find_deprecated_source_hits(sql)
    assert len(hits) == 1
    assert hits[0][1] == 2


def test_multiline_block_comment_preserves_line_numbers():
    sql = "/* block\ncomment */\nSELECT id FROM datalake_hr_system_clean.employee_info"
    hits = find_deprecated_source_hits(sql)
    assert len(hits) == 1
    assert hits[0][1] == 3


def test_find_people_analytics_sandbox_reference():
    hits = find_deprecated_source_hits(
        "SELECT score FROM datalake_people_analytics_sandbox.performance_review_history"
    )
    assert hits[0][0] == "datalake_people_analytics_sandbox"


def test_sandbox_reference_in_line_comment_not_flagged():
    sql = (
        "-- datalake_people_analytics_sandbox.ta_funnel_accumulated was retired\n"
        "SELECT id FROM datalake_workable_redshift_clean.applications"
    )
    hits = find_deprecated_source_hits(sql)
    assert hits == []
