import pytest

from bietlejuice.consumers.api_consumers.gsheets_consumer import GsheetsConsumer


class TestGsheetsConsumerRecordsFromGrid:
    def test_records_from_grid_uses_configured_header_row(self):
        grid = [
            ["Title row"],
            [],
            [],
            [],
            ["", "Line", "Neotribe", "Objective"],
            ["", "Growth", "Broker XP", "Improve conversion"],
        ]

        records = GsheetsConsumer._records_from_grid(grid, header_row=5)

        assert records == [
            {
                "": "",
                "Line": "Growth",
                "Neotribe": "Broker XP",
                "Objective": "Improve conversion",
            }
        ]

    def test_records_from_grid_raises_when_header_row_is_out_of_range(self):
        with pytest.raises(ValueError, match="fewer rows than header_row"):
            GsheetsConsumer._records_from_grid([["only row"]], header_row=5)
