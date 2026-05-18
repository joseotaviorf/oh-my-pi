"""
Unit tests for CoreVisitSparkJob.
"""

from argparse import Namespace
from unittest.mock import Mock, patch

from dags.core.core_visit.spark_jobs.load_core_visit import CoreVisitSparkJob


class TestCoreVisitSparkJob:
    """Test class for CoreVisitSparkJob."""

    def test_create_core_model_basic_functionality(
        self,
        spark_session,
        visit_df,
        visit_status_log_df,
        house_df,
        house_listing_relation_df,
        ebdb_user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
        mock_date_partitioning_helper,
    ):
        """Test basic functionality of create_core_model method."""

        # Create a mock for spark.read
        mock_read = Mock()
        mock_table = Mock()
        mock_read.table.return_value = mock_table

        # Configure return values for different tables
        def side_effect(table_name):
            if "visit_status_log" in table_name:
                return visit_status_log_df
            elif "house_listing_relation" in table_name:
                return house_listing_relation_df
            elif "ebdb_user" in table_name or "user" in table_name:
                return ebdb_user_df
            elif "house" in table_name:
                return house_df
            else:  # visit table
                return visit_df

        mock_table.filter = lambda x: mock_table
        mock_read.table.side_effect = side_effect

        # Mock table reads
        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):
            # Create job and run
            job = CoreVisitSparkJob()
            args = Namespace(load_start_date=None, load_end_date=None)
            result_df = job.create_core_model(spark_session, args)

            # Assertions
            assert result_df is not None
            result_data = result_df.collect()
            assert len(result_data) > 0

            # Check that basic columns exist
            columns = result_df.columns
            expected_columns = [
                "id_visit",
                "id_house",
                "id_visitor",
                "id_owner",
                "id_agent",
                "code",
                "status",
                "computed_status",
                "type",
                "business_context",
                "last_event_type",
                "cancellation_reason",
                "is_fixed_agent",
                "dt_visit",
                "ts_visit",
                "ts_visit_requested",
                "ts_visit_confirmed",
                "ts_visit_done",
                "ts_visit_canceled",
                "ts_visit_unsuccessful",
                "ts_created",
                "ts_updated",
                "ts_load",
                "sk_core_visit",
                "year",
                "month",
                "day",
            ]

            for col in expected_columns:
                assert col in columns, f"Column {col} missing from result"

    def test_process_last_event(
        self, spark_session, visit_status_log_df, mock_configuration_service
    ):
        """Test _process_last_event method."""
        job = CoreVisitSparkJob()
        result_df = job._process_last_event(visit_status_log_df)

        result_data = result_df.collect()

        # Should have one row per visit with the last event
        visit_ids = [row["id_visit"] for row in result_data]
        assert len(set(visit_ids)) == len(visit_ids), "Should have unique visits"

        # Check specific cases
        visit_1_data = [row for row in result_data if row["id_visit"] == 1][0]
        assert visit_1_data["last_event_type"] == "VISIT_CONFIRMED"

        visit_2_data = [row for row in result_data if row["id_visit"] == 2][0]
        assert visit_2_data["last_event_type"] == "VISIT_DONE"

        visit_3_data = [row for row in result_data if row["id_visit"] == 3][0]
        assert visit_3_data["last_event_type"] == "VISIT_CANCELED"

    def test_process_all_events(
        self, spark_session, visit_status_log_df, mock_configuration_service
    ):
        """Test _process_all_events method."""
        job = CoreVisitSparkJob()
        result_df = job._process_all_events(visit_status_log_df)

        result_data = result_df.collect()

        # Check visit 2 (has VISIT_DONE)
        visit_2_data = [row for row in result_data if row["id_visit"] == 2][0]
        assert visit_2_data["ts_visit_requested"] is not None
        assert visit_2_data["ts_visit_confirmed"] is not None
        assert visit_2_data["ts_visit_done"] is not None
        assert visit_2_data["cancellation_reason"] is None

        # Check visit 3 (has cancellation)
        visit_3_data = [row for row in result_data if row["id_visit"] == 3][0]
        assert visit_3_data["cancellation_reason"] == "Owner not available"
        assert visit_3_data["ts_visit_canceled"] is not None

    def test_create_core_model_with_date_filtering(
        self,
        spark_session,
        visit_df,
        visit_status_log_df,
        house_df,
        house_listing_relation_df,
        ebdb_user_df,
        mock_configuration_service,
        mock_surrogate_keys_helper,
        mock_date_partitioning_helper,
    ):
        """Test create_core_model with date filtering for incremental loads."""

        # Create a mock for spark.read
        mock_read = Mock()
        mock_table = Mock()
        mock_read.table.return_value = mock_table

        # Configure return values for different tables
        def side_effect(table_name):
            if "visit_status_log" in table_name:
                return visit_status_log_df
            elif "house_listing_relation" in table_name:
                return house_listing_relation_df
            elif "ebdb_user" in table_name or "user" in table_name:
                return ebdb_user_df
            elif "house" in table_name:
                return house_df
            else:  # visit table
                return visit_df

        # Mock filter to simulate date filtering
        def mock_filter(condition):
            # Simulate filtering by returning only records within date range
            # visit_4 has ts_updated = 2022-12-25 (before range) and should be excluded
            # visits 1, 2, 3 have ts_updated in 2025-01-01 to 2025-01-03 (within range)
            filtered_data = visit_df.collect()
            filtered_data = [
                row for row in filtered_data if row["id"] != 4
            ]  # Exclude visit 4
            return spark_session.createDataFrame(filtered_data, visit_df.schema)

        mock_table.filter = mock_filter
        mock_read.table.side_effect = side_effect

        # Mock table reads with filtering
        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):
            # Create job and run with date filtering
            job = CoreVisitSparkJob()
            mock_args = Namespace()
            mock_args.load_start_date = "2025-01-01"
            mock_args.load_end_date = "2025-01-31"

            result_df = job.create_core_model(spark_session, mock_args)

            result_data = result_df.select("id_visit", "ts_updated").collect()

            # Check that only visits within the date range are included
            result_ids = [row["id_visit"] for row in result_data]
            assert 1 in result_ids, "visit_1 should be included (within date range)"
            assert 2 in result_ids, "visit_2 should be included (within date range)"
            assert 3 in result_ids, "visit_3 should be included (within date range)"
            assert 4 not in result_ids, (
                "visit_4 should be excluded (outside date range)"
            )

    def test_join_all_data_complex_owner_logic(
        self,
        spark_session,
        visit_df,
        visit_status_log_df,
        house_df,
        house_listing_relation_df,
        ebdb_user_df,
        mock_configuration_service,
    ):
        """Test the complex owner resolution logic in _join_all_data."""
        job = CoreVisitSparkJob()

        # Process events data
        vsl_last_event_df = job._process_last_event(visit_status_log_df)
        all_events_df = job._process_all_events(visit_status_log_df)

        result_df = job._join_all_data(
            visit_df,
            vsl_last_event_df,
            all_events_df,
            house_df,
            house_listing_relation_df,
            ebdb_user_df,
        )

        result_data = result_df.collect()

        # Check that owner resolution works correctly
        # Visit 1: id_house=1001 → id_related="5001" → user.id=5001
        # Visit 2: id_house=1002 → id_related="owner_uuid_2" → user.uuid_person="owner_uuid_2" (id=5002)
        # Visit 3: id_house=1003 → id_related="5003" → user.id=5003
        # Visit 4: id_house=1004 → no house_listing_relation → fallback to house.id_user=4004
        visit_1_data = [row for row in result_data if row["id_visit"] == 1][0]
        assert visit_1_data["id_owner"] == 5001, (
            "Visit 1 should get owner via numeric id match"
        )

        visit_2_data = [row for row in result_data if row["id_visit"] == 2][0]
        assert visit_2_data["id_owner"] == 5002, (
            "Visit 2 should get owner via uuid_person match"
        )

        visit_3_data = [row for row in result_data if row["id_visit"] == 3][0]
        assert visit_3_data["id_owner"] == 5003, (
            "Visit 3 should get owner via numeric id match"
        )

        visit_4_data = [row for row in result_data if row["id_visit"] == 4][0]
        assert visit_4_data["id_owner"] == 4004, (
            "Visit 4 should get owner from house.id_user (fallback)"
        )

    def test_load_methods_call_correct_tables(
        self, spark_session, mock_configuration_service
    ):
        """Test that load methods call the correct table names."""
        job = CoreVisitSparkJob()

        config = {
            "VISIT_TABLE": "test.visit",
            "VISIT_STATUS_LOG_TABLE": "test.visit_status_log",
            "HOUSE_TABLE": "test.house",
            "HOUSE_LISTING_RELATION_TABLE": "test.house_listing_relation",
            "EBDB_USER_TABLE": "test.ebdb_user",
        }

        # Create a mock for spark.read
        mock_read = Mock()
        mock_table = Mock()
        mock_read.table.return_value = mock_table

        with patch.object(
            type(spark_session), "read", new_callable=lambda: mock_read, create=True
        ):
            # Test each load method
            args = Namespace(load_start_date=None, load_end_date=None)

            job._load_visit_data(spark_session, config, args)
            mock_read.table.assert_called_with("test.visit")

            job._load_visit_status_log_data(spark_session, config, args)
            mock_read.table.assert_called_with("test.visit_status_log")

            job._load_house_data(spark_session, config)
            mock_read.table.assert_called_with("test.house")

            job._load_house_listing_relation_data(spark_session, config)
            mock_read.table.assert_called_with("test.house_listing_relation")

            job._load_user_data(spark_session, config)
            mock_read.table.assert_called_with("test.ebdb_user")

    def test_visit_status_log_event_aggregation_edge_cases(
        self, spark_session, mock_configuration_service
    ):
        """Test edge cases in visit status log event aggregation."""
        from datetime import datetime

        from pyspark.sql.types import (
            LongType,
            StringType,
            StructField,
            StructType,
            TimestampType,
        )

        # Create edge case data
        schema = StructType(
            [
                StructField("id_visit", LongType(), True),
                StructField("event_type", StringType(), True),
                StructField("reason", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )

        # Visit with multiple cancellation events
        data = [
            (1, "VISIT_REQUEST_CANCELED", "First reason", datetime(2025, 1, 1, 9, 0)),
            (1, "VISIT_CANCELED", "Second reason", datetime(2025, 1, 1, 10, 0)),
            (2, "VISIT_REQUESTED", None, datetime(2025, 1, 2, 9, 0)),
            (2, "VISIT_UNSUCCESSFUL", None, datetime(2025, 1, 2, 10, 0)),
        ]

        edge_case_df = spark_session.createDataFrame(data, schema)

        job = CoreVisitSparkJob()
        result_df = job._process_all_events(edge_case_df)
        result_data = result_df.collect()

        # Visit 1 should have the latest cancellation reason
        visit_1_data = [row for row in result_data if row["id_visit"] == 1][0]
        assert visit_1_data["cancellation_reason"] in ["First reason", "Second reason"]
        assert visit_1_data["ts_visit_canceled"] is not None

        # Visit 2 should have unsuccessful timestamp
        visit_2_data = [row for row in result_data if row["id_visit"] == 2][0]
        assert visit_2_data["ts_visit_unsuccessful"] is not None

    def test_load_config_method(self, spark_session, mock_configuration_service):
        """Test _load_config method."""
        job = CoreVisitSparkJob()
        config = job.get_visit_config()

        expected_keys = [
            "ENTITY_TYPE",
            "VISIT_TABLE",
            "VISIT_STATUS_LOG_TABLE",
            "HOUSE_TABLE",
            "HOUSE_LISTING_RELATION_TABLE",
            "EBDB_USER_TABLE",
        ]

        for key in expected_keys:
            assert key in config, f"Config should contain {key}"

        assert config["ENTITY_TYPE"] == "VISIT"
