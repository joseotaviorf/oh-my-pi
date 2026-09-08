"""Unit tests for the reverse_anonymization validation gsheet export job.

No Spark/Databricks runtime required: pyspark and bietlejuice modules are mocked
in ``sys.modules`` before importing the module under test.
"""

import sys
from unittest.mock import MagicMock

sys.modules.setdefault("quintoandar_logger", MagicMock())
sys.modules.setdefault("quintoandar_gsheets_api_client.clients", MagicMock())
sys.modules.setdefault("quintoandar_gsheets_api_client.producer", MagicMock())
sys.modules.setdefault("bietlejuice.base.api.api_enum", MagicMock())
sys.modules.setdefault("bietlejuice.base.spark", MagicMock())
sys.modules.setdefault("bietlejuice.base.validation.spark_args", MagicMock())
sys.modules.setdefault("bietlejuice.clients.db_clients", MagicMock())
sys.modules.setdefault(
    "bietlejuice.consumers.api_consumers.gsheets_consumer", MagicMock()
)

from dags.governance.reverse_anonymization.spark_jobs import (  # noqa: E402
    load_results_into_gsheet as job,
)


class TestGetPendingValidationRows:
    def test_empty_sheet_returns_no_pending_rows(self):
        # arrange - every entity was evaluated, so the tab holds only its header
        gsheets_consumer = MagicMock()
        gsheets_consumer.read.return_value = []

        # act
        result = job._get_pending_validation_rows(
            gsheets_consumer, "Validation", "sheet-id"
        )

        # assert
        assert result == []
        gsheets_consumer.parse_data_on_dataframe.assert_not_called()

    def test_rows_without_manual_eval_are_kept(self):
        # arrange
        gsheets_consumer = MagicMock()
        sheet_data = [{"id_entity": "datalake_x.table_y.column_z", "manual_eval": ""}]
        gsheets_consumer.read.return_value = sheet_data
        pending_rows = [["datalake_x.table_y.column_z", ""]]
        dataframe = gsheets_consumer.parse_data_on_dataframe.return_value
        dataframe.filter.return_value.rdd.map.return_value.collect.return_value = (
            pending_rows
        )

        # act
        result = job._get_pending_validation_rows(
            gsheets_consumer, "Validation", "sheet-id"
        )

        # assert
        assert result == pending_rows
        gsheets_consumer.parse_data_on_dataframe.assert_called_once_with(
            sheet_data, "pii_scan_results_validation", is_partitioned=False
        )
        dataframe.filter.assert_called_once_with("manual_eval == ''")
