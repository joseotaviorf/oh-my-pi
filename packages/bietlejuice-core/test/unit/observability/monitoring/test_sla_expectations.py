import logging

from bietlejuice.observability.monitoring.sla_expectations import (
    CHECK_EMPTY_PARTITION,
    CHECK_STALE_DATA,
    EmptyPartitionCheck,
    StaleDataCheck,
    TableSla,
    dump_expectations_json,
    load_expectations_from_json,
    load_sla_expectations,
)


class TestParseChecks:
    def test_empty_partition_check(self):
        sla = TableSla(checks=(EmptyPartitionCheck(),))
        assert sla.has_empty_partition()
        assert sla.stale_data_checks() == ()

    def test_stale_data_check(self):
        check = StaleDataCheck(column="ts_load", max_age_hours=36)
        sla = TableSla(checks=(check,))
        assert not sla.has_empty_partition()
        assert sla.stale_data_checks() == (check,)


class TestLoadSlaExpectations:
    def _write_sla(self, root, rel_path: str, content: str) -> None:
        path = root / rel_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def test_glob_and_parse(self, tmp_path):
        self._write_sla(
            tmp_path,
            "people/hr_pipeline/sla/dw/fact_employees.yml",
            """
database_name: dw_people
table_name: fact_employees
checks:
  - type: empty_partition
""",
        )
        expectations = load_sla_expectations(str(tmp_path))
        assert ("dw_people", "fact_employees") in expectations
        sla = expectations[("dw_people", "fact_employees")]
        assert sla.has_empty_partition()

    def test_stale_data_check_parsed(self, tmp_path):
        self._write_sla(
            tmp_path,
            "pilot/sla/enrich/example.yml",
            """
database_name: datalake_example
table_name: example
checks:
  - type: empty_partition
  - type: stale_data
    column: ts_load
    max_age_hours: 36
""",
        )
        sla = load_sla_expectations(str(tmp_path))[("datalake_example", "example")]
        assert sla.has_empty_partition()
        assert len(sla.stale_data_checks()) == 1
        assert sla.stale_data_checks()[0].column == "ts_load"
        assert sla.stale_data_checks()[0].max_age_hours == 36

    def test_arrival_rejected(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "legacy/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
arrival:
  mute: true
""",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}

    def test_duplicate_check_type_rejected(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "dup/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
checks:
  - type: empty_partition
  - type: empty_partition
""",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}

    def test_missing_stale_column_rejected(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "bad/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
checks:
  - type: stale_data
    max_age_hours: 24
""",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}

    def test_invalid_max_age_hours_rejected(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "bad/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
checks:
  - type: stale_data
    column: ts_load
    max_age_hours: 0
""",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}

    def test_missing_checks_rejected(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "missing/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
""",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}


class TestExpectationsJsonRoundTrip:
    def test_dump_and_load_preserves_sla(self):
        original = {
            ("datalake_example", "example"): TableSla(
                checks=(
                    EmptyPartitionCheck(),
                    StaleDataCheck(column="ts_load", max_age_hours=36),
                )
            )
        }
        restored = load_expectations_from_json(dump_expectations_json(original))
        assert restored == original

    def test_json_contains_check_types(self):
        payload = dump_expectations_json(
            {
                ("db", "table"): TableSla(
                    checks=(
                        EmptyPartitionCheck(),
                        StaleDataCheck(column="ts_assessed", max_age_hours=36),
                    )
                )
            }
        )
        assert CHECK_EMPTY_PARTITION in payload
        assert CHECK_STALE_DATA in payload
        assert "ts_assessed" in payload
