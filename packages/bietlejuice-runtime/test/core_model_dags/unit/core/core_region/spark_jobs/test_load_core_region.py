"""
Unit tests for CoreRegionSparkJob.
"""

from argparse import Namespace
from unittest.mock import patch

import pytest

from dags.core.core_region.spark_jobs.load_core_region import CoreRegionSparkJob

EXPECTED_OUTPUT_COLUMNS = {
    "sk_core_region",
    "id_region",
    "id_parent_region",
    "id_city_region",
    "id_macro_region",
    "region_name",
    "city_region_name",
    "level",
    "id_state",
    "state_name",
    "state_abbreviation",
    "id_country",
    "country_code",
    "country_name",
    "country_default_timezone",
    "region_phone_ddd",
    "greater_region",
    "has_rent_operation",
    "has_sale_operation",
    "ts_region_created",
    "ts_region_updated",
    "ts_load",
    "year",
    "month",
    "day",
}


class TestCoreRegionSparkJobConfig:
    """Tests focused on job configuration and initialisation."""

    def test_get_region_config_returns_expected_keys(self, mock_configuration_service):
        """get_region_config must return all configuration keys."""
        job = CoreRegionSparkJob()
        config = job.get_region_config()

        expected_keys = [
            "ENTITY_TYPE",
            "REGION_TABLE",
            "REGION_BUSINESS_CONTEXTS_TABLE",
            "REGION_CONFIG_TABLE",
            "STATE_TABLE",
            "COUNTRY_TABLE",
        ]
        for key in expected_keys:
            assert key in config, f"Config should contain '{key}'"

        assert config["ENTITY_TYPE"] == "REGION"

    def test_job_name_constant(self):
        """JOB_NAME must equal 'core_region'."""
        from dags.core.core_region.spark_jobs.load_core_region import JOB_NAME

        assert JOB_NAME == "core_region"

    def test_job_initialisation(self, mock_configuration_service):
        """CoreRegionSparkJob can be instantiated without errors."""
        job = CoreRegionSparkJob()
        assert job.job_name == "core_region"

    def test_job_has_required_methods(self, mock_configuration_service):
        """CoreRegionSparkJob exposes all required public methods."""
        job = CoreRegionSparkJob()
        for method in ("get_region_config", "create_core_model", "run", "parse_args"):
            assert hasattr(job, method), f"Job should have method '{method}'"


class TestLoadRegionData:
    """Tests for the _load_region_data helper method."""

    def test_calls_correct_table(
        self, spark_session, region_df, mock_configuration_service
    ):
        """_load_region_data must read the table specified by REGION_TABLE."""
        job = CoreRegionSparkJob()
        config = job.get_region_config()

        with patch.object(spark_session, "table", return_value=region_df) as mock_table:
            args = Namespace(load_start_date=None, load_end_date=None)
            job._load_region_data(spark_session, config, args)
            mock_table.assert_called_once_with(config["REGION_TABLE"])

    def test_full_load_returns_all_rows(
        self, spark_session, region_df, mock_configuration_service
    ):
        """Full load (no dates) must return every row from the region table."""
        job = CoreRegionSparkJob()
        config = job.get_region_config()

        with patch.object(spark_session, "table", return_value=region_df):
            args = Namespace(load_start_date=None, load_end_date=None)
            result = job._load_region_data(spark_session, config, args)

        assert result.count() == region_df.count()

    def test_incremental_load_filters_by_ts_updated(
        self, spark_session, region_df, mock_configuration_service
    ):
        """Incremental load must restrict rows using coalesce(ts_updated, ts_created) date window."""
        job = CoreRegionSparkJob()
        config = job.get_region_config()

        with patch.object(spark_session, "table", return_value=region_df):
            args = Namespace(load_start_date="2025-01-01", load_end_date="2025-01-31")
            result = job._load_region_data(spark_session, config, args)

        result_ids = [row["id"] for row in result.select("id").collect()]

        assert 1 in result_ids, "Region 1 (ts_updated 2025-01-15) should be included"
        assert 2 in result_ids, "Region 2 (ts_updated 2025-01-20) should be included"
        assert 6 in result_ids, "Region 6 (ts_updated 2025-01-10) should be included"
        assert 3 in result_ids and 5 in result_ids, (
            "Parents with Jan ts_updated included"
        )

        assert 4 not in result_ids, (
            "Region 4 (ts_updated 2022-12-25) should be excluded"
        )

    def test_empty_string_dates_treated_as_full_load(
        self, spark_session, region_df, mock_configuration_service
    ):
        """Empty-string date args must not trigger date filtering."""
        job = CoreRegionSparkJob()
        config = job.get_region_config()

        with patch.object(spark_session, "table", return_value=region_df):
            args = Namespace(load_start_date="", load_end_date="")
            result = job._load_region_data(spark_session, config, args)

        assert result.count() == region_df.count()


class TestCreateCoreModelBasic:
    """Tests for the end-to-end create_core_model method."""

    def test_returns_non_empty_dataframe(self, core_model_df):
        """create_core_model must return a non-empty DataFrame."""
        assert core_model_df is not None
        assert core_model_df.count() > 0

    def test_expected_output_columns(self, core_model_df):
        """Output DataFrame must contain exactly the expected set of columns."""
        actual_columns = set(core_model_df.columns)
        missing = EXPECTED_OUTPUT_COLUMNS - actual_columns
        extra = actual_columns - EXPECTED_OUTPUT_COLUMNS

        assert not missing, f"Missing columns in output: {missing}"
        assert not extra, f"Unexpected extra columns in output: {extra}"

    def test_all_source_tables_are_read(
        self,
        spark_session,
        core_region_job,
        table_side_effect,
        mock_surrogate_keys_helper,
    ):
        """create_core_model must read all distinct source tables."""
        read_tables = []

        def recording_side_effect(table_name):
            read_tables.append(table_name)
            return table_side_effect(table_name)

        with patch.object(spark_session, "table", side_effect=recording_side_effect):
            core_region_job.create_core_model(
                spark_session, Namespace(load_start_date=None, load_end_date=None)
            )

        expected_tables = {
            "test.region",
            "test.region_business_context_served",
            "test.region_config",
            "test.state",
            "test.country",
        }
        assert expected_tables == set(read_tables), (
            f"Expected tables {expected_tables}, got {set(read_tables)}"
        )


class TestCreateCoreModelFilters:
    """Tests for filter logic inside create_core_model."""

    def test_filters_regions_without_country_code(
        self,
        spark_session,
        core_region_job,
        region_df_with_unknown_state,
        region_business_contexts_df,
        region_config_df,
        state_df_with_unknown,
        country_df_with_null_code,
        mock_surrogate_keys_helper,
    ):
        """Regions whose country_code resolves to NULL must be excluded from the output."""

        def side_effect(table_name):
            mapping = {
                "test.region": region_df_with_unknown_state,
                "test.region_business_context_served": region_business_contexts_df,
                "test.region_config": region_config_df,
                "test.state": state_df_with_unknown,
                "test.country": country_df_with_null_code,
            }
            return mapping[table_name]

        with patch.object(spark_session, "table", side_effect=side_effect):
            result_df = core_region_job.create_core_model(
                spark_session, Namespace(load_start_date=None, load_end_date=None)
            )

        result_ids = [
            row["id_region"] for row in result_df.select("id_region").collect()
        ]

        # 'Unknown City' (id_region=9) links to state 20 → country 200 → code=NULL
        assert 9 not in result_ids, "Region with null code must be filtered out"

        # Normal regions (id_region=1, 3, 5) link to state 10 → country 100 → code='BR'
        assert 1 in result_ids, "Region 1 with valid country_code should be kept"

    def test_output_has_no_null_country_code(self, core_model_df):
        """country_code must never be NULL in the output (enforced by the IS NOT NULL filter)."""
        null_count = core_model_df.filter(
            core_model_df["country_code"].isNull()
        ).count()
        assert null_count == 0, f"Found {null_count} rows with null country_code"


class TestCreateCoreModelBusinessContext:
    """Tests for the business-context aggregation logic."""

    def test_has_rent_operation_true_when_rent_context_exists(self, core_model_df):
        """has_rent_operation must be True for regions that have a RENT business context."""
        # Region 1 (Moema) has RENT only
        row = core_model_df.filter(core_model_df["id_region"] == 1).collect()
        assert len(row) == 1
        assert row[0]["has_rent_operation"] is True

    def test_has_sale_operation_false_when_no_sale_context(self, core_model_df):
        """has_sale_operation must be False for regions that have no SALE business context."""
        row = core_model_df.filter(core_model_df["id_region"] == 1).collect()
        assert len(row) == 1
        assert row[0]["has_sale_operation"] is False

    def test_has_both_operations_when_both_contexts_exist(self, core_model_df):
        """Both flags must be True for regions that have both RENT and SALE contexts."""
        # Region 2 (Ibirapuera) has both RENT and SALE
        row = core_model_df.filter(core_model_df["id_region"] == 2).collect()
        assert len(row) == 1
        assert row[0]["has_rent_operation"] is True
        assert row[0]["has_sale_operation"] is True

    def test_operation_flags_default_to_false_without_context(self, core_model_df):
        """Regions with no entry in region_business_contexts_df must have both flags False."""
        # Regions 3, 5, 6 have no business context rows
        for region_id in (3, 5, 6):
            row = core_model_df.filter(
                core_model_df["id_region"] == region_id
            ).collect()
            assert len(row) == 1, f"Region {region_id} should be in the output"
            assert row[0]["has_rent_operation"] is False, (
                f"Region {region_id} should have has_rent_operation=False"
            )
            assert row[0]["has_sale_operation"] is False, (
                f"Region {region_id} should have has_sale_operation=False"
            )


class TestCreateCoreModelHierarchy:
    """Tests for city / macro resolution, DDD, and greater_region (enrich parity)."""

    def test_subregion_city_and_macro_ids(self, core_model_df):
        """SubRegiao rows inherit cidade id and name from the two-hop parent chain."""
        row = core_model_df.filter(core_model_df["id_region"] == 1).collect()[0]
        assert row["id_city_region"] == 5
        assert row["id_macro_region"] == 3
        assert row["city_region_name"] == "São Paulo"
        assert row["region_phone_ddd"] == "11"
        assert row["greater_region"] == "Grande São Paulo"

    def test_cidade_row_city_fields_are_self(self, core_model_df):
        """Cidade-level row uses self for city id/name; no macro parent id."""
        row = core_model_df.filter(core_model_df["id_region"] == 5).collect()[0]
        assert row["id_city_region"] == 5
        assert row["id_macro_region"] is None
        assert row["city_region_name"] == "São Paulo"
        assert row["greater_region"] == "Grande São Paulo"

    def test_macro_regiao_city_from_parent_cidade(self, core_model_df):
        """MacroRegiao row resolves city from immediate parent Cidade."""
        row = core_model_df.filter(core_model_df["id_region"] == 3).collect()[0]
        assert row["id_city_region"] == 5
        assert row["id_macro_region"] == 5
        assert row["city_region_name"] == "São Paulo"
        assert row["region_phone_ddd"] == "11"


class TestCreateCoreModelJoins:
    """Tests for join correctness (state, country, hierarchy)."""

    def test_state_and_country_columns_populated(self, core_model_df):
        """State and country attributes must be populated for all output rows."""
        for row in core_model_df.collect():
            region_id = row["id_region"]
            assert row["state_name"] is not None, (
                f"Region {region_id}: state_name is null"
            )
            assert row["state_abbreviation"] is not None, (
                f"Region {region_id}: state_abbreviation is null"
            )
            assert row["country_code"] is not None, (
                f"Region {region_id}: country_code is null"
            )
            assert row["country_name"] is not None, (
                f"Region {region_id}: country_name is null"
            )

    def test_id_state_propagated_from_hierarchy(self, core_model_df):
        """id_state must be resolved through the parent hierarchy for SubRegiao rows."""
        # SubRegiao (id=1) has id_state=None; it inherits id_state=10 via MacroRegiao → Cidade
        row = core_model_df.filter(core_model_df["id_region"] == 1).collect()
        assert len(row) == 1
        assert row[0]["id_state"] == 10, (
            "SubRegiao should inherit id_state=10 from the Cidade ancestor"
        )

    def test_country_code_value(self, core_model_df):
        """country_code must match the value from the country table."""
        for row in core_model_df.collect():
            assert row["country_code"] == "BR", (
                f"Region {row['id_region']}: expected country_code='BR'"
            )

    def test_country_name_normalized_like_enrich_region(self, core_model_df):
        """Brazil/Mexico labels match enrich_region (English), not raw country.name."""
        for row in core_model_df.collect():
            assert row["country_name"] == "Brazil", (
                f"Region {row['id_region']}: expected country_name='Brazil'"
            )

    def test_country_name_mexico_when_state_id_country_is_two(
        self,
        spark_session,
        core_region_job,
        mock_configuration_service,
        mock_surrogate_keys_helper,
    ):
        """id_country=2 maps to Mexico (same as for_rent enrich_region)."""
        from datetime import datetime

        from pyspark.sql.types import (
            LongType,
            StringType,
            StructField,
            StructType,
            TimestampType,
        )

        region_schema = StructType(
            [
                StructField("id", LongType(), True),
                StructField("id_parent_region", LongType(), True),
                StructField("name", StringType(), True),
                StructField("level", StringType(), True),
                StructField("id_state", LongType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("ts_updated", TimestampType(), True),
                StructField("ts_database_transaction", TimestampType(), True),
            ]
        )
        ts = datetime(2025, 1, 1)
        region_mx = spark_session.createDataFrame(
            [(1, None, "CDMX", "Cidade", 50, ts, ts, ts)], region_schema
        )
        state_mx = spark_session.createDataFrame(
            [(50, "CMX", "CMX", 2)],
            ["id", "name", "abbreviation", "id_country"],
        )
        country_mx = spark_session.createDataFrame(
            [(2, "MX", "México", "America/Mexico_City")],
            ["id", "code", "name", "default_timezone"],
        )
        empty_bc = spark_session.createDataFrame(
            [], "id_region long, business_context string"
        )
        empty_cfg = spark_session.createDataFrame(
            [], "id_region long, phone_ddd string"
        )

        def side_effect(table_name):
            return {
                "test.region": region_mx,
                "test.region_business_context_served": empty_bc,
                "test.region_config": empty_cfg,
                "test.state": state_mx,
                "test.country": country_mx,
            }[table_name]

        with patch.object(spark_session, "table", side_effect=side_effect):
            out = core_region_job.create_core_model(
                spark_session, Namespace(load_start_date=None, load_end_date=None)
            )
        row = out.collect()[0]
        assert row["country_name"] == "Mexico"
        assert row["country_code"] == "MX"


class TestCreateCoreModelDateFilter:
    """Tests for incremental-load date filtering in create_core_model."""

    def test_date_filter_excludes_old_region(
        self,
        spark_session,
        core_region_job,
        table_side_effect,
        mock_surrogate_keys_helper,
    ):
        """Regions with ts_updated outside the load window must not appear in the output."""
        with patch.object(spark_session, "table", side_effect=table_side_effect):
            result_df = core_region_job.create_core_model(
                spark_session,
                Namespace(load_start_date="2025-01-01", load_end_date="2025-01-31"),
            )

        result_ids = [
            row["id_region"] for row in result_df.select("id_region").collect()
        ]

        assert 4 not in result_ids, (
            "Region 4 (ts_updated 2022-12-25) should be excluded by the date filter"
        )

    def test_date_filter_keeps_regions_in_window(
        self,
        spark_session,
        core_region_job,
        table_side_effect,
        mock_surrogate_keys_helper,
    ):
        """Regions with ts_updated inside the load window must be present in the output."""
        with patch.object(spark_session, "table", side_effect=table_side_effect):
            result_df = core_region_job.create_core_model(
                spark_session,
                Namespace(load_start_date="2025-01-01", load_end_date="2025-01-31"),
            )

        result_ids = [
            row["id_region"] for row in result_df.select("id_region").collect()
        ]

        assert 1 in result_ids, "Region 1 should be included"
        assert 2 in result_ids, "Region 2 should be included"
        assert 6 in result_ids, (
            "Region 6 included via ts_updated though CDC date is old"
        )

    def test_incremental_resolves_parents_when_only_child_ts_updated_in_window(
        self,
        spark_session,
        core_region_job,
        table_side_effect_skewed,
        mock_surrogate_keys_helper,
    ):
        """Full region dimension join: only child in incremental window still gets cidade/macro ids."""
        with patch.object(spark_session, "table", side_effect=table_side_effect_skewed):
            result_df = core_region_job.create_core_model(
                spark_session,
                Namespace(load_start_date="2025-01-01", load_end_date="2025-01-31"),
            )

        rows = result_df.collect()
        assert len(rows) == 1
        row = rows[0]
        assert row["id_region"] == 1
        assert row["id_city_region"] == 5
        assert row["id_macro_region"] == 3
        assert row["city_region_name"] == "São Paulo"

    def test_full_load_includes_all_regions(
        self,
        spark_session,
        core_region_job,
        table_side_effect,
        mock_surrogate_keys_helper,
    ):
        """Full load (no dates) must include all regions, including the old one."""
        with patch.object(spark_session, "table", side_effect=table_side_effect):
            result_df = core_region_job.create_core_model(
                spark_session,
                Namespace(load_start_date=None, load_end_date=None),
            )

        result_ids = [
            row["id_region"] for row in result_df.select("id_region").collect()
        ]

        for expected_id in (1, 2, 3, 4, 5, 6):
            assert expected_id in result_ids, (
                f"Region {expected_id} should be present in the full load"
            )


class TestCreateCoreModelPartitions:
    """Tests for the year/month/day partition columns."""

    def test_year_month_day_derived_from_ts_region_updated(self, core_model_df):
        """year, month, day columns must match the date parts of ts_region_updated for every row."""
        for row in core_model_df.collect():
            ts = row["ts_region_updated"]
            assert row["year"] == ts.year, (
                f"Region {row['id_region']}: year={row['year']}, expected {ts.year}"
            )
            assert row["month"] == ts.month, (
                f"Region {row['id_region']}: month={row['month']}, expected {ts.month}"
            )
            assert row["day"] == ts.day, (
                f"Region {row['id_region']}: day={row['day']}, expected {ts.day}"
            )

    def test_ts_load_is_not_null(self, core_model_df):
        """ts_load must be populated (set to current_timestamp) for all rows."""
        null_count = core_model_df.filter(core_model_df["ts_load"].isNull()).count()
        assert null_count == 0, f"Found {null_count} rows with null ts_load"


class TestCreateCoreModelSurrogateKey:
    """Tests for surrogate key generation."""

    def test_sk_core_region_column_present(self, core_model_df):
        """sk_core_region must be present in the output."""
        assert "sk_core_region" in core_model_df.columns

    def test_sk_core_region_not_null(self, core_model_df):
        """sk_core_region must not contain null values."""
        null_count = core_model_df.filter(
            core_model_df["sk_core_region"].isNull()
        ).count()
        assert null_count == 0, f"Found {null_count} rows with null sk_core_region"


# Pytest markers consistent with other core model DAG tests
pytestmark = [
    pytest.mark.core_model,
    pytest.mark.spark,
    pytest.mark.dag_specific,
]
