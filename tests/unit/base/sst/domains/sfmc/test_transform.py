import pytest

from bietlejuice.base.sst.domains.sfmc.raw.transform import normalize_row


class TestNormalizeRow:
    @pytest.mark.parametrize(
        "raw_row, expected",
        [
            ("abc", {"raw_record": "abc"}),
            (
                {"values": {"id_user": 123}, "keys": {"pk_event_user": "K1"}},
                {"id_user": 123, "pk_event_user": "K1"},
            ),
            ({"id_user": 123}, {"id_user": 123}),
        ],
    )
    def test_normalize_row(self, raw_row, expected):
        assert normalize_row(raw_row) == expected

    def test_non_dict_row_is_wrapped_as_raw_record(self):
        assert normalize_row(42) == {"raw_record": "42"}

    def test_values_key_takes_precedence_over_keys_for_duplicate_fields(self):
        raw_row = {
            "values": {"id_user": 1},
            "keys": {"id_user": 999, "extra": "x"},
        }
        result = normalize_row(raw_row)
        assert result["id_user"] == 1
        assert result["extra"] == "x"

    def test_keys_without_values_returns_raw_row(self):
        raw_row = {"keys": {"pk": "K1"}, "id_user": 1}
        assert normalize_row(raw_row) == raw_row
