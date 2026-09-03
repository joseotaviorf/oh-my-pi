import pytest

from bietlejuice.jobs.planning_and_performance.reverse_bpo_table_selection import (
    is_table_selected,
    parse_requested_tables,
)


class TestParseRequestedTables:
    @pytest.mark.parametrize(
        "raw_value",
        [None, "", "   ", "null", "NULL", "none", "[]", "[ ]"],
    )
    def test_returns_empty_list_when_no_table_was_requested(self, raw_value):
        assert parse_requested_tables(raw_value) == []

    def test_parses_the_json_list_rendered_by_the_trigger_form(self):
        assert parse_requested_tables('["segments_perspective", "fcr_metric"]') == [
            "segments_perspective",
            "fcr_metric",
        ]

    def test_parses_a_json_string_holding_a_single_table(self):
        assert parse_requested_tables('"segments_perspective"') == [
            "segments_perspective"
        ]

    def test_parses_a_comma_separated_string(self):
        assert parse_requested_tables("segments_perspective,fcr_metric") == [
            "segments_perspective",
            "fcr_metric",
        ]

    def test_parses_a_comma_separated_json_string(self):
        assert parse_requested_tables('"segments_perspective, fcr_metric"') == [
            "segments_perspective",
            "fcr_metric",
        ]

    def test_parses_a_bare_table_name(self):
        assert parse_requested_tables("segments_perspective") == [
            "segments_perspective"
        ]

    def test_strips_whitespace_and_drops_empty_entries(self):
        assert parse_requested_tables('[" segments_perspective ", "", "  "]') == [
            "segments_perspective"
        ]

    def test_drops_trailing_separators(self):
        assert parse_requested_tables("segments_perspective,") == [
            "segments_perspective"
        ]


class TestIsTableSelected:
    @pytest.mark.parametrize("raw_value", [None, "", "null", "[]"])
    def test_selects_every_table_when_nothing_was_requested(self, raw_value):
        assert is_table_selected("segments_perspective", raw_value) is True

    def test_selects_a_requested_table(self):
        raw_value = '["segments_perspective", "fcr_metric"]'

        assert is_table_selected("fcr_metric", raw_value) is True

    def test_does_not_select_a_table_outside_the_request(self):
        raw_value = '["segments_perspective", "fcr_metric"]'

        assert is_table_selected("backlog_metric", raw_value) is False

    def test_ignores_casing_and_surrounding_whitespace(self):
        assert is_table_selected(" Segments_Perspective ", '["segments_perspective"]')

    def test_does_not_select_any_table_for_an_unknown_request(self):
        raw_value = '["segments_perspectives"]'

        assert is_table_selected("segments_perspective", raw_value) is False
