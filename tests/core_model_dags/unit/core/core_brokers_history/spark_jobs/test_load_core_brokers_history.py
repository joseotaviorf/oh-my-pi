"""
Unit tests for CoreBrokersHistorySparkJob.
"""

from types import SimpleNamespace
from unittest.mock import patch

from dags.core.core_brokers_history.spark_jobs.load_core_brokers_history import (
    CoreBrokersHistorySparkJob,
)

EXPECTED_COMPANY_COLUMNS = {
    "id_event",
    "id_company",
    "sk_core_company",
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

EXPECTED_COMPANY_PRODUCT_COLUMNS = {
    "id_event",
    "id_company_product",
    "sk_core_company_product",
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


def _make_args(table_name, start="2026-01-01", end="2026-02-01"):
    return SimpleNamespace(
        table_name=table_name,
        load_start_date=start,
        load_end_date=end,
    )


class TestCoreBrokersHistoryCompanySchema:

    def test_create_core_model_company_returns_13_columns(
        self,
        spark_session,
        transactional_company_df,
        mock_configuration_company_history,
    ):
        job = CoreBrokersHistorySparkJob()
        args = _make_args("company_history")
        with patch(
            "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_company_df,
        ):
            result = job.create_core_model(spark_session, args)

        assert len(result.columns) == 13
        assert set(result.columns) == EXPECTED_COMPANY_COLUMNS

    def test_event_origin_matches_config(
        self,
        spark_session,
        transactional_company_df,
        mock_configuration_company_history,
    ):
        job = CoreBrokersHistorySparkJob()
        args = _make_args("company_history")
        with patch(
            "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_company_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["event_origin"] == "test.transactional_company"

    def test_update_emits_only_changed_company_columns(
        self,
        spark_session,
        transactional_company_df,
        mock_configuration_company_history,
    ):
        job = CoreBrokersHistorySparkJob()
        args = _make_args("company_history")
        with patch(
            "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_company_df,
        ):
            result = job.create_core_model(spark_session, args)

        update_events = [
            r
            for r in result.collect()
            if r["ts_transaction"].day == 11 and r["ts_transaction"].month == 1
        ]
        names = {r["event_name"] for r in update_events}
        assert "ev_status" in names
        assert "ev_company_name" not in names


class TestCoreBrokersHistoryCompanyProductSchema:

    def test_create_core_model_company_product_returns_13_columns(
        self,
        spark_session,
        transactional_company_product_df,
        mock_configuration_company_product_history,
    ):
        job = CoreBrokersHistorySparkJob()
        args = _make_args("company_product_history")
        with patch(
            "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_company_product_df,
        ):
            result = job.create_core_model(spark_session, args)

        assert len(result.columns) == 13
        assert set(result.columns) == EXPECTED_COMPANY_PRODUCT_COLUMNS

    def test_composite_id_format(
        self,
        spark_session,
        transactional_company_product_df,
        mock_configuration_company_product_history,
    ):
        job = CoreBrokersHistorySparkJob()
        args = _make_args("company_product_history")
        with patch(
            "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_company_product_df,
        ):
            result = job.create_core_model(spark_session, args)

        for row in result.collect():
            assert row["id_company_product"] == "1||30"

    def test_id_event_deterministic(
        self,
        spark_session,
        transactional_company_product_df,
        mock_configuration_company_product_history,
    ):
        job = CoreBrokersHistorySparkJob()
        args = _make_args("company_product_history")
        with patch(
            "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_company_product_df,
        ):
            r1 = job.create_core_model(spark_session, args)
        with patch(
            "dags.core.core_brokers_history.spark_jobs.load_core_brokers_history"
            ".HistoricalHelper.load_transactional_data",
            return_value=transactional_company_product_df,
        ):
            r2 = job.create_core_model(spark_session, args)

        assert {x["id_event"] for x in r1.collect()} == {
            x["id_event"] for x in r2.collect()
        }
