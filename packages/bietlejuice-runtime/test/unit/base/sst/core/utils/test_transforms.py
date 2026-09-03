"""Unit tests for bietlejuice.base.sst.core.utils.transforms."""

from unittest import mock

from bietlejuice.base.sst.core.utils import transforms


class TestGetRowsToUpdate:
    def test_reads_current_rows_and_joins_distinct_keys(self):
        # arrange
        spark = mock.MagicMock()
        current_df = spark.table.return_value.where.return_value
        update_df = mock.MagicMock()

        # act
        result = transforms.get_rows_to_update(
            spark, "core.services", update_df, ["id_session", "id_task"]
        )

        # assert: only the _is_current filter is applied to the target and the
        # join runs on the distinct context keys of the batch.
        spark.table.assert_called_once_with("core.services")
        current_df.where.assert_not_called()
        update_df.select.assert_called_once_with("id_session", "id_task")
        unique_rows = update_df.select.return_value.distinct.return_value
        current_df.join.assert_called_once_with(
            unique_rows, on=["id_session", "id_task"], how="inner"
        )
        assert result is current_df.join.return_value

    def test_accepts_single_context_column(self):
        # arrange
        spark = mock.MagicMock()
        current_df = spark.table.return_value.where.return_value
        update_df = mock.MagicMock()

        # act
        transforms.get_rows_to_update(spark, "core.cases", update_df, "id_case")

        # assert: a plain string key is wrapped into the join key list.
        update_df.select.assert_called_once_with("id_case")
        current_df.join.assert_called_once_with(
            update_df.select.return_value.distinct.return_value,
            on=["id_case"],
            how="inner",
        )
