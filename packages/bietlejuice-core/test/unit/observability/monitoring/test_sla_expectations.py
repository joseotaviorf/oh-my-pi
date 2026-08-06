import logging

from bietlejuice.observability.monitoring.sla_expectations import (
    ArrivalExpectation,
    _parse_days_of_week,
    dump_expectations_json,
    format_arrival_expectation_brief,
    format_arrival_expectation_summary,
    load_expectations_from_json,
    load_sla_expectations,
)


class TestParseDaysOfWeek:
    def test_all_returns_none(self):
        assert _parse_days_of_week("all") is None

    def test_weekdays_expands_mon_fri(self):
        assert _parse_days_of_week("weekdays") == {0, 1, 2, 3, 4}

    def test_list_of_day_names(self):
        assert _parse_days_of_week(["mon", "wed", "fri"]) == {0, 2, 4}

    def test_single_day_string(self):
        assert _parse_days_of_week("sat") == {5}


class TestFormatArrivalExpectationBrief:
    def test_none_expectation(self):
        assert (
            format_arrival_expectation_brief(None)
            == "no SLA (any empty partition alerts)"
        )

    def test_daily_with_hour(self):
        assert (
            format_arrival_expectation_brief(ArrivalExpectation(earliest_hour=8))
            == "daily from 08h BRT"
        )

    def test_weekdays_with_hour(self):
        assert (
            format_arrival_expectation_brief(
                ArrivalExpectation(
                    days_of_week={0, 1, 2, 3, 4},
                    earliest_hour=9,
                )
            )
            == "weekdays from 09h BRT"
        )


class TestFormatArrivalExpectationSummary:
    def test_none_expectation(self):
        assert (
            format_arrival_expectation_summary(None)
            == "none configured (alert on any empty run partition)"
        )

    def test_weekdays_with_hour_and_reason(self):
        summary = format_arrival_expectation_summary(
            ArrivalExpectation(
                days_of_week={0, 1, 2, 3, 4},
                earliest_hour=9,
                reason="Upstream runs weekdays at 09:00",
            )
        )
        assert "weekdays (Mon–Fri)" in summary
        assert "09:00" in summary
        assert "Upstream runs weekdays at 09:00" in summary


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
arrival:
  days_of_week: weekdays
  earliest_hour: 9
  mute: false
""",
        )
        expectations = load_sla_expectations(str(tmp_path))
        assert ("dw_people", "fact_employees") in expectations
        expectation = expectations[("dw_people", "fact_employees")]
        assert expectation.days_of_week == {0, 1, 2, 3, 4}
        assert expectation.earliest_hour == 9
        assert expectation.mute is False

    def test_malformed_file_is_skipped(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "broken/sla/dw/fact_x.yml",
            "not: [valid, structure",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}

    def test_missing_keys_are_skipped(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "missing/sla/dw/fact_x.yml",
            "table_name: fact_x\narrival:\n  mute: true\n",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}

    def test_mute_flag(self, tmp_path):
        self._write_sla(
            tmp_path,
            "muted/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
arrival:
  mute: true
""",
        )
        expectations = load_sla_expectations(str(tmp_path))
        assert expectations[("dw_x", "fact_x")].mute is True

    def test_all_sugar(self, tmp_path):
        self._write_sla(
            tmp_path,
            "daily/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
arrival:
  days_of_week: all
""",
        )
        expectations = load_sla_expectations(str(tmp_path))
        assert expectations[("dw_x", "fact_x")].days_of_week is None

    def test_custom_timezone(self, tmp_path):
        self._write_sla(
            tmp_path,
            "tz/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
arrival:
  timezone: UTC
  earliest_hour: 12
""",
        )
        expectations = load_sla_expectations(str(tmp_path))
        assert expectations[("dw_x", "fact_x")].timezone == "UTC"

    def test_no_arrival_facet_is_ignored(self, tmp_path):
        self._write_sla(
            tmp_path,
            "no_arrival/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
""",
        )
        expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}

    def test_invalid_arrival_facet_is_skipped(self, tmp_path, caplog):
        self._write_sla(
            tmp_path,
            "bad_arrival/sla/dw/fact_x.yml",
            """
database_name: dw_x
table_name: fact_x
arrival: weekdays
""",
        )
        with caplog.at_level(logging.WARNING):
            expectations = load_sla_expectations(str(tmp_path))
        assert expectations == {}


class TestExpectationsJsonRoundTrip:
    def test_dump_and_load_preserves_expectation(self):
        original = {
            ("dw_rent", "fact_contracts"): ArrivalExpectation(
                days_of_week={0, 1, 2, 3, 4},
                earliest_hour=9,
                mute=False,
                timezone="America/Sao_Paulo",
                reason="weekday load",
            )
        }
        restored = load_expectations_from_json(dump_expectations_json(original))
        assert restored == original
