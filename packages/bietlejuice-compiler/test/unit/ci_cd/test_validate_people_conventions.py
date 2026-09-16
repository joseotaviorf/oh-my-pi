"""Unit tests for people_conventions_validator."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from scripts.ci_cd.people_conventions_validator import (  # noqa: E402
    Finding,
    _dq_path_for_sql,
    validate_column_order_pair,
    validate_dq_file,
    validate_grain_documentation,
    validate_subqueries_in_sql,
)


def _write(path: Path, content: str) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    return path


def test_dq_clean_requires_has_size_variation(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/clean/sample.yml",
        """
---
table_name: datalake_pin_core_clean.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
column_level_validations: {}
""",
    )
    findings = validate_dq_file(dq_path)
    assert any(f.check == "dq_has_size_variation" for f in findings)


def test_dq_rejects_error_on_non_sk_complete(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/dw/sample.yml",
        """
---
table_name: dw_people.dim_sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
column_level_validations:
  person_number:
    is_complete:
      severity_level: Error
""",
    )
    findings = validate_dq_file(dq_path)
    assert any(f.check == "dq_severity" for f in findings)


def test_dq_accepts_valid_clean_file(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/clean/sample.yml",
        """
---
table_name: datalake_pin_core_clean.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
  has_size_variation:
    variation_type: percentage
    greater_than_or_equal_to: -10
    less_than_or_equal_to: 25
    severity_level: Error
column_level_validations:
  id_sample:
    is_complete:
      severity_level: Warning
""",
    )
    assert validate_dq_file(dq_path) == []


def test_dq_has_size_error_requires_greater_than(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/clean/sample.yml",
        """
---
table_name: datalake_pin_core_clean.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    severity_level: Error
""",
    )
    findings = validate_dq_file(dq_path)
    assert any(f.check == "dq_has_size_floor" for f in findings)


def test_dq_omitted_size_variation_bound_uses_default(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/clean/sample.yml",
        """
---
table_name: datalake_pin_core_clean.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
  has_size_variation:
    variation_type: percentage
    greater_than_or_equal_to: -10
    severity_level: Error
""",
    )
    findings = validate_dq_file(dq_path)
    assert not any(f.check == "dq_size_variation_bounds" for f in findings)


def test_dq_accepts_non_default_size_variation_with_comment(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/clean/sample.yml",
        """
---
table_name: datalake_pin_core_clean.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
  # Weekly ingest can swing more than default bounds during backfills
  has_size_variation:
    variation_type: percentage
    greater_than_or_equal_to: -20
    less_than_or_equal_to: 40
    severity_level: Error
column_level_validations:
  id_sample:
    is_complete:
      severity_level: Warning
""",
    )
    assert validate_dq_file(dq_path) == []


def test_dq_custom_requires_intent_comment(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/enrich/sample.yml",
        """
---
table_name: datalake_people.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
column_level_validations:
  salary_amount_must_not_be_negative:
    custom:
      constraint: |-
        (SELECT COUNT(*) FROM datalake_people.sample WHERE salary_amount < 0) = 0
      severity_level: Warning
""",
    )
    findings = validate_dq_file(dq_path)
    assert any(f.check == "dq_custom_comment" for f in findings)


def test_dq_custom_accepts_inline_comment(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/enrich/sample.yml",
        """
---
table_name: datalake_people.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
column_level_validations:
  salary_amount_must_not_be_negative:
    custom:
      # Salary must be non-negative
      constraint: |-
        (SELECT COUNT(*) FROM datalake_people.sample WHERE salary_amount < 0) = 0
      severity_level: Warning
""",
    )
    assert not any(f.check == "dq_custom_comment" for f in validate_dq_file(dq_path))


def test_dq_one_row_per_must_be_error(tmp_path: Path):
    dq_path = _write(
        tmp_path / "data_quality/enrich/sample.yml",
        """
---
table_name: datalake_people.sample
alert_channel: PEOPLE_ALERTS
table_level_validations:
  has_size:
    greater_than: 1
    severity_level: Error
column_level_validations:
  one_row_per_person:
    custom:
      # Grain uniqueness
      constraint: |-
        (SELECT COUNT(*) FROM (
          SELECT person_number FROM datalake_people.sample
          GROUP BY person_number HAVING COUNT(*) > 1
        )) = 0
      severity_level: Warning
""",
    )
    findings = validate_dq_file(dq_path)
    assert any(f.check == "dq_grain_severity" for f in findings)


def test_column_order_mismatch(tmp_path: Path):
    sql_path = _write(
        tmp_path / "queries/clean/sample.sql",
        """
SELECT
  id_a,
  id_b
FROM
  datalake_pin_core_raw.sample
""",
    )
    meta_path = _write(
        tmp_path / "metadata/clean/sample.yml",
        """
database_name: datalake_pin_core_clean
table_name: sample
owner: people-analytics
domain: people
description: Sample table for tests.
columns:
  id_b:
    description: Second identifier.
    lineage:
      - datalake_pin_core_raw.sample.id_b
  id_a:
    description: First identifier.
    lineage:
      - datalake_pin_core_raw.sample.id_a
""",
    )
    findings = validate_column_order_pair(sql_path, meta_path)
    assert any(f.check == "column_order" for f in findings)


def test_column_order_match(tmp_path: Path):
    sql_path = _write(
        tmp_path / "queries/clean/sample.sql",
        """
SELECT
  id_a,
  id_b
FROM
  datalake_pin_core_raw.sample
""",
    )
    meta_path = _write(
        tmp_path / "metadata/clean/sample.yml",
        """
database_name: datalake_pin_core_clean
table_name: sample
owner: people-analytics
domain: people
description: Sample table for tests.
columns:
  id_a:
    description: First identifier.
    lineage:
      - datalake_pin_core_raw.sample.id_a
  id_b:
    description: Second identifier.
    lineage:
      - datalake_pin_core_raw.sample.id_b
""",
    )
    assert validate_column_order_pair(sql_path, meta_path) == []


def test_grain_documentation_required_for_dw(tmp_path: Path):
    meta_path = _write(
        tmp_path / "metadata/dw/sample.yml",
        """
database_name: dw_people
table_name: fact_sample
owner: people-analytics
domain: people
description: Workforce sample fact without explicit grain wording.
columns:
  sk_sample:
    description: Surrogate key.
""",
    )
    findings = validate_grain_documentation(meta_path, None)
    assert any(f.check == "grain_documentation" for f in findings)


def test_grain_documentation_passes_with_phrase(tmp_path: Path):
    meta_path = _write(
        tmp_path / "metadata/dw/sample.yml",
        """
database_name: dw_people
table_name: fact_sample
owner: people-analytics
domain: people
description: |
  Sample workforce fact.
  One row per assignment_number per calendar day.
columns:
  sk_sample:
    description: Surrogate key.
""",
    )
    assert validate_grain_documentation(meta_path, None) == []


def test_subquery_in_from_flagged(tmp_path: Path):
    sql_path = _write(
        tmp_path / "queries/enrich/sample.sql",
        """
SELECT
  x.id
FROM
  (
    SELECT id FROM datalake_people.base
  ) AS x
""",
    )
    findings = validate_subqueries_in_sql(sql_path)
    assert any(f.check == "subquery_in_from" for f in findings)


def test_cte_subquery_not_flagged(tmp_path: Path):
    sql_path = _write(
        tmp_path / "queries/enrich/sample.sql",
        """
WITH base AS (
  SELECT id FROM datalake_people.base
)
SELECT
  base.id
FROM
  base
""",
    )
    assert validate_subqueries_in_sql(sql_path) == []


def test_finding_format_includes_check_name():
    finding = Finding("path/file.yml", "dq_severity", "message", line_no=3)
    formatted = finding.format()
    assert "[dq_severity]" in formatted
    assert "path/file.yml:3" in formatted
    assert "→ Fix:" in formatted
    assert "people_data_quality.mdc" in formatted


def test_finding_format_deprecated_source_hint():
    finding = Finding(
        "path/query.sql",
        "deprecated_source:datalake_hr_system",
        "deprecated upstream reference",
        line_no=10,
    )
    formatted = finding.format()
    assert "→ Fix:" in formatted
    assert "pin_*" in formatted or "datalake_people" in formatted


def test_validate_deprecated_sources_skips_legacy_dag(tmp_path: Path):
    from scripts.ci_cd.people_conventions_validator import (  # noqa: E402
        validate_deprecated_sources_in_sql,
    )

    sql_path = tmp_path / "dags/people/dw_employee/queries/dw/fact.sql"
    sql_path.parent.mkdir(parents=True, exist_ok=True)
    sql_path.write_text(
        "SELECT id FROM datalake_hr_system_clean.employee_info",
        encoding="utf-8",
    )
    assert validate_deprecated_sources_in_sql(sql_path) == []


def test_validate_deprecated_sources_flags_pin_dag(tmp_path: Path):
    from scripts.ci_cd.people_conventions_validator import (  # noqa: E402
        validate_deprecated_sources_in_sql,
    )

    sql_path = tmp_path / "dags/people/pin/queries/enrich/sample.sql"
    sql_path.parent.mkdir(parents=True, exist_ok=True)
    sql_path.write_text(
        "SELECT id FROM datalake_hr_system_clean.employee_info",
        encoding="utf-8",
    )
    findings = validate_deprecated_sources_in_sql(sql_path)
    assert any(f.check.startswith("deprecated_source:") for f in findings)


def test_dq_path_for_sql_skips_reverse_layer(tmp_path: Path):
    sql_path = tmp_path / "dags/people/reverse_reports/queries/reverse/sample.sql"
    sql_path.parent.mkdir(parents=True, exist_ok=True)
    sql_path.write_text("SELECT 1", encoding="utf-8")
    assert _dq_path_for_sql(sql_path) is None
