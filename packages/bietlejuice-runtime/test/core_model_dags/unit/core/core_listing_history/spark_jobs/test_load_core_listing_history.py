"""
Unit tests for CoreListingHistorySparkJob.

Verifies the 15-column narrow event-log schema, CDC + derived event behaviour,
merge configuration, idempotency hashing, and run_pipeline empty-target bypass
— following the patterns used for core_contract_history / core_house_history.
"""

from types import SimpleNamespace
from unittest.mock import MagicMock, patch

from conftest import (
    TEST_AUX_TABLE,
    TEST_LBC_TABLE,
    _load_transactional_side_effect,
)
from pyspark.sql.utils import AnalysisException

from dags.core.core_listing_history.spark_jobs.load_core_listing_history import (
    CoreListingHistorySparkJob,
)

_MODULE = "dags.core.core_listing_history.spark_jobs.load_core_listing_history"

EXPECTED_HISTORY_COLUMNS = {
    "id_event",
    "id_house",
    "id_house_listing",
    "business_context",
    "sk_core_listing_history",
    "event_name",
    "event_type",
    "value",
    "payload",
    "ts_transaction",
    "event_origin",
    "ts_load",
    "year",
    "month",
    "day",
}


def _make_args(start="2026-01-01", end="2026-02-01"):
    return SimpleNamespace(
        table_name="listing_history",
        load_start_date=start,
        load_end_date=end,
    )


class TestCoreListingHistorySchema:
    def test_create_core_model_returns_15_column_history_schema(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        assert len(result.columns) == 15
        assert set(result.columns) == EXPECTED_HISTORY_COLUMNS

    def test_payload_is_null_for_all_rows(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["payload"] is None

    def test_event_type_is_cdc_or_derived(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        types_found = {r["event_type"] for r in result.collect()}
        assert types_found <= {"cdc", "derived"}
        assert "cdc" in types_found
        assert "derived" in types_found


class TestCoreListingHistoryEventDetection:
    def test_lbc_update_emits_ownership_change_for_rent(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        ownership_events = [
            r
            for r in result.collect()
            if r["event_name"] == "ev_ownership" and r["id_house"] == "99"
        ]
        assert len(ownership_events) >= 2
        values = sorted({r["value"] for r in ownership_events})
        assert "STANDARD" in values
        assert "THIRD_PARTY" in values

    def test_sale_lbc_emits_status_events_only_for_sale_context(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        status_from_lbc = [
            r
            for r in result.collect()
            if r["event_name"] == "ev_status" and r["event_origin"] == TEST_LBC_TABLE
        ]
        assert all(r["business_context"] == "SALE" for r in status_from_lbc)

    def test_rent_status_and_status_reason_events_come_from_aux_table(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        """RENT status / status_reason must not be emitted from LBC CDC — only aux."""
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        rows = result.collect()

        rent_status = [
            r
            for r in rows
            if r["event_name"] == "ev_status" and r["business_context"] == "RENT"
        ]
        rent_reason = [
            r
            for r in rows
            if r["event_name"] == "ev_status_reason" and r["business_context"] == "RENT"
        ]
        assert len(rent_status) >= 1
        assert len(rent_reason) >= 1
        for r in rent_status + rent_reason:
            assert r["event_origin"] == TEST_AUX_TABLE
            assert r["event_type"] == "derived"

        forbidden = [
            r
            for r in rows
            if r["business_context"] == "RENT"
            and r["event_name"] in ("ev_status", "ev_status_reason")
            and r["event_origin"] == TEST_LBC_TABLE
        ]
        assert not forbidden, "RENT status must not originate from LBC transactional"

    def test_sale_id_house_listing_always_uses_version_zero_suffix(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        """SALE listings use id_house_listing = concat(id_house, '000') as in core_listing."""
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        sale_rows = [r for r in result.collect() if r["business_context"] == "SALE"]
        assert len(sale_rows) >= 1
        for r in sale_rows:
            id_h = str(r["id_house"])
            expected_suffix = f"{id_h}000"
            assert str(r["id_house_listing"]) == expected_suffix

    def test_price_update_emits_ev_price_for_rent_only_on_aluguel_change(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        rent_price = [
            r
            for r in result.collect()
            if r["event_name"] == "ev_price"
            and r["business_context"] == "RENT"
            and r["id_house"] == "99"
        ]
        assert len(rent_price) >= 1
        assert any(r["value"] == "1100" for r in rent_price)

    def test_listing_category_na_when_version0_and_no_category_row(
        self,
        spark_session,
        register_listing_history_views_no_category,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        """Same rule as core_listing: version 0 + missing category → NA."""
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        cat_events = [
            r
            for r in result.collect()
            if r["event_name"] == "ev_category" and r["id_house"] == "99"
        ]
        assert len(cat_events) >= 1
        assert any(r["value"] == "NA" for r in cat_events)


class TestCoreListingHistoryIdempotency:
    def test_id_event_is_deterministic_hash(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result1 = job.create_core_model(spark_session, args)
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result2 = job.create_core_model(spark_session, args)

        ids1 = {r["id_event"] for r in result1.collect()}
        ids2 = {r["id_event"] for r in result2.collect()}
        assert ids1 == ids2

    def test_id_event_is_sha256_hex_string(
        self,
        spark_session,
        register_listing_history_views,
        lbc_transactional_df,
        imovel_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = _make_args()
        with patch(
            f"{_MODULE}.HistoricalHelper.load_transactional_data",
            side_effect=_load_transactional_side_effect(
                lbc_transactional_df, imovel_transactional_df
            ),
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["id_event"] is not None
            assert len(row["id_event"]) == 64


class TestMergeStrategyConfig:
    def test_merge_on_historical_includes_listing_natural_key_and_partition(
        self, mock_configuration_listing_history
    ):
        job = CoreListingHistorySparkJob()
        merge_on = job.get_config("merge_on_historical", required=True)

        assert merge_on == [
            "id_house_listing",
            "business_context",
            "event_name",
            "ts_transaction",
            "year",
            "month",
            "day",
        ]

    def test_when_matched_update_condition_is_false(
        self, mock_configuration_listing_history
    ):
        job = CoreListingHistorySparkJob()
        condition = job.get_config(
            "when_matched_update_condition_historical",
            required=False,
            default=None,
        )
        assert condition == "FALSE"


class TestTargetTableEmptyDetection:
    def test_returns_true_when_table_does_not_exist(self, spark_session):
        job = CoreListingHistorySparkJob()
        result = job._is_target_table_empty(
            spark_session, "nonexistent_db.nonexistent_table"
        )
        assert result is True

    def test_returns_true_on_analysis_exception(self, spark_session):
        job = CoreListingHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.side_effect = AnalysisException(
            "Table not found",
        )
        result = job._is_target_table_empty(mock_spark, "bad_db.bad_table")
        assert result is True

    def test_returns_true_when_table_is_empty(self):
        job = CoreListingHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = True
        result = job._is_target_table_empty(mock_spark, "db.empty_table")
        assert result is True

    def test_returns_false_when_table_has_data(self):
        job = CoreListingHistorySparkJob()
        mock_spark = MagicMock()
        mock_spark.catalog.tableExists.return_value = True
        mock_spark.table.return_value.isEmpty.return_value = False
        result = job._is_target_table_empty(mock_spark, "db.populated_table")
        assert result is False


class TestRunPipelineBypass:
    def _make_pipeline_args(self):
        return SimpleNamespace(
            table_name="listing_history",
            load_start_date="2026-01-01",
            load_end_date="2026-02-01",
            partitions="['year', 'month', 'day']",
            schema="core_listing",
            bucket="test-bucket",
        )

    @patch(f"{_MODULE}.DataFrameDeltaTableLoaderPipeline")
    def test_uses_direct_write_when_target_is_empty(
        self,
        mock_pipeline_cls,
        spark_session,
        lbc_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = self._make_pipeline_args()
        with (
            patch.object(job, "_is_target_table_empty", return_value=True),
            patch.object(job, "setup_table_privileges", return_value=None),
        ):
            job.run_pipeline(lbc_transactional_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] is None
        assert call_kwargs["when_matched_update_condition"] is None

    @patch(f"{_MODULE}.DataFrameDeltaTableLoaderPipeline")
    def test_uses_partition_scoped_merge_when_target_has_data(
        self,
        mock_pipeline_cls,
        spark_session,
        lbc_transactional_df,
        mock_configuration_listing_history,
    ):
        job = CoreListingHistorySparkJob()
        args = self._make_pipeline_args()
        with (
            patch.object(job, "_is_target_table_empty", return_value=False),
            patch.object(job, "setup_table_privileges", return_value=None),
        ):
            job.run_pipeline(lbc_transactional_df, args, spark_session)

        call_kwargs = mock_pipeline_cls.call_args[1]
        assert call_kwargs["merge_on"] == [
            "id_house_listing",
            "business_context",
            "event_name",
            "ts_transaction",
            "year",
            "month",
            "day",
        ]
        assert call_kwargs["when_matched_update_condition"] == "FALSE"
