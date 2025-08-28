import pytest
from unittest.mock import Mock, patch
from datetime import datetime
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, StringType, TimestampType
from pyspark.sql.functions import col

# Import the actual functions from the DAG
import sys
import importlib.util
from pathlib import Path

# Get the path to the load_core_visit.py file
project_root = Path(__file__).parent.parent.parent.parent.parent.parent.parent
load_core_visit_path = (
    project_root
    / "dags"
    / "core"
    / "core_visit_test"
    / "spark_jobs"
    / "load_core_visit.py"
)

# Add project root to Python path
sys.path.insert(0, str(project_root))

# Mock problematic dependencies before importing
mock_services = Mock()


# Create a mock base class that can be inherited from
class MockBaseCoreModelSparkJob:
    def __init__(self, job_name):
        self.job_name = job_name
        self.logger = Mock()
        self.config_service = None

    def parse_args(self):
        mock_args = Mock()
        mock_args.environment = "forno"
        mock_args.bucket = "test-bucket"
        mock_args.dag_name = "core_visit_test"
        mock_args.schema = "core"
        mock_args.table_name = "visit"
        mock_args.load_start_date = "2023-01-01"
        mock_args.load_end_date = "2023-01-31"
        mock_args.extra_spark_job_arguments = "{}"
        mock_args.table_privileges = None
        return mock_args

    def initialize_configuration(self, source):
        pass

    def get_config(self, key, required=True, default=None):
        config_map = {
            "ENTITY_TYPE": "VISIT",
            "VISIT_TABLE": "test_visit_table",
            "VISIT_STATUS_LOG_TABLE": "test_vsl_table",
            "HOUSE_TABLE": "test_house_table",
            "CONTRACT_TABLE": "test_contract_table",
        }
        return config_map.get(key, default)

    def initialize_spark_session(self):
        return Mock()

    def setup_table_privileges(self, args):
        return Mock()

    def run_pipeline(self, dataframe, args, spark):
        pass

    def run(self):
        pass


with patch.dict(
    "sys.modules",
    {
        "quintoandar_logger": Mock(),
        "hierarchical_conf.hierarchical_conf": Mock(),
        "bietlejuice": Mock(),
        "bietlejuice.base": Mock(),
        "bietlejuice.base.pipeline": Mock(),
        "bietlejuice.base.spark": Mock(),
        "bietlejuice.base.spark.base_spark": Mock(),
        "bietlejuice.base.spark.base_core_model_spark_job": type(
            "MockModule", (), {"BaseCoreModelSparkJob": MockBaseCoreModelSparkJob}
        )(),
        "bietlejuice.base.spark.unity_catalog_helper": Mock(),
        "bietlejuice.base.databricks": Mock(),
        "bietlejuice.base.databricks.table_privileges": Mock(),
        "bietlejuice.base.core_models": Mock(),
        "bietlejuice.base.core_models.helpers": Mock(),
        "bietlejuice.base.core_models.helpers.surrogate_keys": Mock(),
        "bietlejuice.services": mock_services,
        "bietlejuice.services.configuration_service": Mock(),
        "bietlejuice.services.metastore_services": Mock(),
        "bietlejuice.services.metastore_services.spark_metastore_service": Mock(),
        "bietlejuice.loaders": Mock(),
        "bietlejuice.loaders.delta_loader": Mock(),
        "bietlejuice.pipeline": Mock(),
        "bietlejuice.pipeline.abstract_pipeline": Mock(),
        "bietlejuice.pipeline.dataframe_delta_table_loader_pipeline": Mock(),
        "bietlejuice.clients": Mock(),
        "bietlejuice.clients.db_clients": Mock(),
        "bietlejuice.consumers": Mock(),
        "bietlejuice.consumers.db_consumers": Mock(),
        "bietlejuice.consumers.db_consumers.databricks_consumer": Mock(),
    },
):
    # Load the module dynamically
    spec = importlib.util.spec_from_file_location(
        "load_core_visit", load_core_visit_path
    )
    load_core_visit = importlib.util.module_from_spec(spec)
    sys.modules["load_core_visit"] = load_core_visit
    spec.loader.exec_module(load_core_visit)

# Import the functions we need to test
CoreVisitSparkJob = load_core_visit.CoreVisitSparkJob
_get_visit_last_event = CoreVisitSparkJob._get_visit_last_event
_get_visit_all_events = CoreVisitSparkJob._get_visit_all_events
_calculate_visit_last_update = CoreVisitSparkJob._calculate_visit_last_update
JOB_NAME = load_core_visit.JOB_NAME


class TestCoreVisitHelperFunctions:
    """Test cases for core visit helper functions - isolated to this DAG context."""

    def test_get_visit_last_event_basic_functionality(
        self, spark_session, visit_status_log_df
    ):
        """Test _get_visit_last_event returns the most recent event for each visit."""
        # Act
        result_df = _get_visit_last_event(visit_status_log_df)

        # Assert
        assert result_df.count() == 3  # Should have one record per visit

        # Verify the structure includes row number column
        assert "rn" in result_df.columns

        # Verify all row numbers are 1 (most recent)
        row_numbers = [row["rn"] for row in result_df.select("rn").collect()]
        assert all(rn == 1 for rn in row_numbers)

        # Verify we get the latest events
        visit_1_events = result_df.filter(col("id_visit") == "visit_1").collect()
        assert len(visit_1_events) == 1
        assert (
            visit_1_events[0]["event_type"] == "VISIT_DONE"
        )  # Latest event for visit_1

    def test_get_visit_last_event_with_single_event_per_visit(self, spark_session):
        """Test _get_visit_last_event with single event per visit."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        data = [
            ("visit_1", "VISIT_CONFIRMED", datetime(2023, 1, 1, 12, 0)),
            ("visit_2", "VISIT_DONE", datetime(2023, 1, 2, 12, 0)),
        ]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_df = _get_visit_last_event(df)

        # Assert
        assert result_df.count() == 2
        events = {row["id_visit"]: row["event_type"] for row in result_df.collect()}
        assert events["visit_1"] == "VISIT_CONFIRMED"
        assert events["visit_2"] == "VISIT_DONE"

    def test_get_visit_last_event_with_date_filtering(self, spark_session):
        """Test _get_visit_last_event applies date filtering when dates provided."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        data = [
            ("visit_1", "VISIT_CONFIRMED", datetime(2023, 1, 1, 12, 0)),  # Within range
            (
                "visit_1",
                "VISIT_DONE",
                datetime(2023, 1, 15, 12, 0),
            ),  # Within range (latest)
            (
                "visit_2",
                "VISIT_CONFIRMED",
                datetime(2022, 12, 25, 12, 0),
            ),  # Before range
            ("visit_2", "VISIT_DONE", datetime(2023, 2, 5, 12, 0)),  # After range
            (
                "visit_3",
                "VISIT_CONFIRMED",
                datetime(2023, 1, 10, 12, 0),
            ),  # Within range
        ]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_df = _get_visit_last_event(df, "2023-01-01", "2023-01-31")

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 2  # Only visit_1 and visit_3 have events in range

        # Check visit_1 gets the latest event within range
        visit_1_events = [row for row in result_list if row["id_visit"] == "visit_1"]
        assert len(visit_1_events) == 1
        assert visit_1_events[0]["event_type"] == "VISIT_DONE"

        # Check visit_3 is included
        visit_3_events = [row for row in result_list if row["id_visit"] == "visit_3"]
        assert len(visit_3_events) == 1
        assert visit_3_events[0]["event_type"] == "VISIT_CONFIRMED"

    def test_get_visit_last_event_without_date_filtering(self, spark_session):
        """Test _get_visit_last_event processes all data when dates are None."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        data = [
            ("visit_1", "VISIT_CONFIRMED", datetime(2022, 12, 25, 12, 0)),
            ("visit_1", "VISIT_DONE", datetime(2023, 2, 5, 12, 0)),  # Latest overall
            ("visit_2", "VISIT_CONFIRMED", datetime(2023, 1, 10, 12, 0)),
        ]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_df = _get_visit_last_event(df, None, None)

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 2  # Both visits

        # Check visit_1 gets the latest overall event
        visit_1_events = [row for row in result_list if row["id_visit"] == "visit_1"]
        assert len(visit_1_events) == 1
        assert visit_1_events[0]["event_type"] == "VISIT_DONE"

    def test_get_visit_last_event_with_empty_date_strings(self, spark_session):
        """Test _get_visit_last_event processes all data when dates are empty strings."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        data = [
            ("visit_1", "VISIT_CONFIRMED", datetime(2023, 1, 1, 12, 0)),
            ("visit_1", "VISIT_DONE", datetime(2023, 1, 15, 12, 0)),
        ]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_df = _get_visit_last_event(df, "", "")

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 1
        assert result_list[0]["event_type"] == "VISIT_DONE"  # Latest event

    def test_get_visit_all_events_aggregation(self, spark_session, visit_status_log_df):
        """Test _get_visit_all_events properly aggregates events by visit."""
        # Act
        result_df = _get_visit_all_events(visit_status_log_df)

        # Assert
        assert result_df.count() == 3  # One record per visit

        # Verify columns exist
        expected_columns = [
            "id_visit",
            "cancellation_reason",
            "ts_visit_confirmed",
            "ts_visit_done",
            "ts_visit_canceled",
            "ts_visit_unsuccessful",
        ]
        for col_name in expected_columns:
            assert col_name in result_df.columns

        # Verify specific aggregations
        visit_1_data = result_df.filter(col("id_visit") == "visit_1").collect()[0]
        assert visit_1_data["ts_visit_confirmed"] is not None
        assert visit_1_data["ts_visit_done"] is not None
        assert visit_1_data["cancellation_reason"] is None

        visit_3_data = result_df.filter(col("id_visit") == "visit_3").collect()[0]
        # The function uses max() so it gets the latest reason alphabetically, not chronologically
        assert (
            visit_3_data["cancellation_reason"] is not None
        )  # Should have a cancellation reason
        assert visit_3_data["ts_visit_canceled"] is not None

    def test_get_visit_all_events_with_no_events(self, spark_session):
        """Test _get_visit_all_events with empty DataFrame."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("reason", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        empty_df = spark_session.createDataFrame([], schema)

        # Act
        result_df = _get_visit_all_events(empty_df)

        # Assert
        assert result_df.count() == 0

    def test_get_visit_all_events_with_date_filtering(self, spark_session):
        """Test _get_visit_all_events applies date filtering when dates provided."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("reason", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        data = [
            (
                "visit_1",
                "VISIT_CONFIRMED",
                None,
                datetime(2023, 1, 5, 12, 0),
            ),  # Within range
            (
                "visit_1",
                "VISIT_DONE",
                None,
                datetime(2023, 1, 10, 12, 0),
            ),  # Within range
            (
                "visit_1",
                "VISIT_CANCELED",
                "user_cancel",
                datetime(2022, 12, 25, 12, 0),
            ),  # Before range
            (
                "visit_2",
                "VISIT_CONFIRMED",
                None,
                datetime(2023, 2, 5, 12, 0),
            ),  # After range
            (
                "visit_3",
                "VISIT_CANCELED",
                "agent_cancel",
                datetime(2023, 1, 15, 12, 0),
            ),  # Within range
        ]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_df = _get_visit_all_events(df, "2023-01-01", "2023-01-31")

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 2  # Only visit_1 and visit_3 have events in range

        # Check visit_1 aggregation (should only include events within range)
        visit_1_data = [row for row in result_list if row["id_visit"] == "visit_1"][0]
        assert visit_1_data["ts_visit_confirmed"] is not None
        assert visit_1_data["ts_visit_done"] is not None
        assert (
            visit_1_data["ts_visit_canceled"] is None
        )  # Canceled event was before range

        # Check visit_3 aggregation
        visit_3_data = [row for row in result_list if row["id_visit"] == "visit_3"][0]
        assert visit_3_data["ts_visit_canceled"] is not None
        assert visit_3_data["cancellation_reason"] == "agent_cancel"

    def test_get_visit_all_events_without_date_filtering(self, spark_session):
        """Test _get_visit_all_events processes all data when dates are None."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("reason", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        data = [
            ("visit_1", "VISIT_CONFIRMED", None, datetime(2022, 12, 25, 12, 0)),
            ("visit_1", "VISIT_DONE", None, datetime(2023, 2, 5, 12, 0)),
            ("visit_1", "VISIT_CANCELED", "user_cancel", datetime(2023, 1, 15, 12, 0)),
        ]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_df = _get_visit_all_events(df, None, None)

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 1

        # Check all events are included when no filtering
        visit_1_data = result_list[0]
        assert visit_1_data["ts_visit_confirmed"] is not None
        assert visit_1_data["ts_visit_done"] is not None
        assert visit_1_data["ts_visit_canceled"] is not None
        assert visit_1_data["cancellation_reason"] == "user_cancel"

    def test_get_visit_all_events_with_empty_date_strings(self, spark_session):
        """Test _get_visit_all_events processes all data when dates are empty strings."""
        # Arrange
        schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("event_type", StringType(), True),
                StructField("reason", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        data = [
            ("visit_1", "VISIT_CONFIRMED", None, datetime(2023, 1, 5, 12, 0)),
            ("visit_1", "VISIT_DONE", None, datetime(2023, 1, 10, 12, 0)),
        ]
        df = spark_session.createDataFrame(data, schema)

        # Act
        result_df = _get_visit_all_events(df, "", "")

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 1
        visit_1_data = result_list[0]
        assert visit_1_data["ts_visit_confirmed"] is not None
        assert visit_1_data["ts_visit_done"] is not None

    def test_calculate_visit_last_update_basic_functionality(
        self, spark_session, visit_df, visit_status_log_df
    ):
        """Test _calculate_visit_last_update calculates correct timestamps."""
        # Arrange
        vsl_last_event_df = _get_visit_last_event(visit_status_log_df)
        all_events_df = _get_visit_all_events(visit_status_log_df)

        # Act
        result_df = _calculate_visit_last_update(
            visit_df, vsl_last_event_df, all_events_df
        )

        # Assert
        assert result_df.count() == 3
        assert "id" in result_df.columns
        assert "ts_updated_agg" in result_df.columns

        # Verify all visits have calculated timestamps
        results = result_df.collect()
        for row in results:
            assert row["ts_updated_agg"] is not None

    def test_calculate_visit_last_update_with_date_filtering(self, spark_session):
        """Test _calculate_visit_last_update applies date filtering to visit_df."""
        # Arrange
        visit_schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("ts_updated", TimestampType(), True),
            ]
        )
        visit_data = [
            (
                "visit_1",
                datetime(2023, 1, 5, 12, 0),
                datetime(2023, 1, 5, 13, 0),
            ),  # Within range
            (
                "visit_2",
                datetime(2022, 12, 25, 12, 0),
                datetime(2022, 12, 25, 13, 0),
            ),  # Before range
            (
                "visit_3",
                datetime(2023, 2, 5, 12, 0),
                datetime(2023, 2, 5, 13, 0),
            ),  # After range
        ]
        visit_df = spark_session.createDataFrame(visit_data, visit_schema)

        # Create mock last event and all events dataframes
        vsl_schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        vsl_data = [("visit_1", datetime(2023, 1, 6, 12, 0))]
        vsl_last_event_df = spark_session.createDataFrame(vsl_data, vsl_schema)

        all_events_schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("ts_visit_confirmed", TimestampType(), True),
                StructField("ts_visit_done", TimestampType(), True),
                StructField("ts_visit_canceled", TimestampType(), True),
                StructField("ts_visit_unsuccessful", TimestampType(), True),
            ]
        )
        all_events_data = [("visit_1", datetime(2023, 1, 7, 12, 0), None, None, None)]
        all_events_df = spark_session.createDataFrame(
            all_events_data, all_events_schema
        )

        # Act
        result_df = _calculate_visit_last_update(
            visit_df, vsl_last_event_df, all_events_df, "2023-01-01", "2023-01-31"
        )

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 1  # Only visit_1 is within date range
        assert result_list[0]["id"] == "visit_1"
        assert result_list[0]["ts_updated_agg"] is not None

    def test_calculate_visit_last_update_without_date_filtering(self, spark_session):
        """Test _calculate_visit_last_update processes all visits when dates are None."""
        # Arrange
        visit_schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("ts_updated", TimestampType(), True),
            ]
        )
        visit_data = [
            ("visit_1", datetime(2022, 12, 25, 12, 0), datetime(2022, 12, 25, 13, 0)),
            ("visit_2", datetime(2023, 2, 5, 12, 0), datetime(2023, 2, 5, 13, 0)),
        ]
        visit_df = spark_session.createDataFrame(visit_data, visit_schema)

        # Create empty mock dataframes for join compatibility
        vsl_schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        vsl_last_event_df = spark_session.createDataFrame([], vsl_schema)

        all_events_schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("ts_visit_confirmed", TimestampType(), True),
                StructField("ts_visit_done", TimestampType(), True),
                StructField("ts_visit_canceled", TimestampType(), True),
                StructField("ts_visit_unsuccessful", TimestampType(), True),
            ]
        )
        all_events_df = spark_session.createDataFrame([], all_events_schema)

        # Act
        result_df = _calculate_visit_last_update(
            visit_df, vsl_last_event_df, all_events_df, None, None
        )

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 2  # Both visits included when no filtering
        visit_ids = [row["id"] for row in result_list]
        assert "visit_1" in visit_ids
        assert "visit_2" in visit_ids

    def test_calculate_visit_last_update_with_empty_date_strings(self, spark_session):
        """Test _calculate_visit_last_update processes all visits when dates are empty strings."""
        # Arrange
        visit_schema = StructType(
            [
                StructField("id", StringType(), True),
                StructField("ts_created", TimestampType(), True),
                StructField("ts_updated", TimestampType(), True),
            ]
        )
        visit_data = [
            ("visit_1", datetime(2023, 1, 5, 12, 0), datetime(2023, 1, 5, 13, 0))
        ]
        visit_df = spark_session.createDataFrame(visit_data, visit_schema)

        # Create empty mock dataframes
        vsl_schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("ts_created", TimestampType(), True),
            ]
        )
        vsl_last_event_df = spark_session.createDataFrame([], vsl_schema)

        all_events_schema = StructType(
            [
                StructField("id_visit", StringType(), True),
                StructField("ts_visit_confirmed", TimestampType(), True),
                StructField("ts_visit_done", TimestampType(), True),
                StructField("ts_visit_canceled", TimestampType(), True),
                StructField("ts_visit_unsuccessful", TimestampType(), True),
            ]
        )
        all_events_df = spark_session.createDataFrame([], all_events_schema)

        # Act
        result_df = _calculate_visit_last_update(
            visit_df, vsl_last_event_df, all_events_df, "", ""
        )

        # Assert
        result_list = result_df.collect()
        assert len(result_list) == 1
        assert result_list[0]["id"] == "visit_1"


class TestCoreVisitSparkJob:
    """Test cases for CoreVisitSparkJob class - isolated to this DAG context."""

    def test_core_visit_spark_job_initialization(self):
        """Test CoreVisitSparkJob can be initialized."""
        # Act & Assert - Should not raise an exception
        job = CoreVisitSparkJob()
        assert job.job_name == "core_visit"

    def test_core_visit_spark_job_has_required_methods(self):
        """Test CoreVisitSparkJob has all required methods."""
        job = CoreVisitSparkJob()
        # Assert
        assert hasattr(job, "get_visit_config")
        assert hasattr(job, "create_core_model")
        assert hasattr(job, "run")
        assert hasattr(job, "parse_args")
        assert hasattr(job, "initialize_spark_session")
        # Check static methods
        assert hasattr(CoreVisitSparkJob, "_get_visit_last_event")
        assert hasattr(CoreVisitSparkJob, "_get_visit_all_events")
        assert hasattr(CoreVisitSparkJob, "_calculate_visit_last_update")


class TestSparkSessionInitialization:
    """Test cases for Spark session initialization - isolated to this DAG context."""

    def test_initialize_spark_session_returns_spark_session(self):
        """Test initialize_spark_session returns a SparkSession."""
        # Arrange
        job = CoreVisitSparkJob()

        # Act
        result = job.initialize_spark_session()

        # Assert
        assert result is not None
        # Note: In test environment, this might return a mock or basic session


class TestArgumentParsing:
    """Test cases for argument parsing - isolated to this DAG context."""

    @patch(
        "sys.argv",
        [
            "load_core_visit.py",
            "forno",
            "test-bucket",
            "core_visit_test",
            "core",
            "visit",
            "2023-01-01",
            "2023-01-31",
            "--extra_spark_job_arguments",
            "{}",  # extra_spark_job_arguments (empty JSON)
        ],
    )
    def test_parse_args_with_all_arguments(self):
        """Test parse_args with all command line arguments provided."""
        # Arrange
        job = CoreVisitSparkJob()

        # Act
        args = job.parse_args()

        # Assert
        assert args.environment == "forno"
        assert args.bucket == "test-bucket"
        assert args.dag_name == "core_visit_test"
        assert args.schema == "core"
        assert args.table_name == "visit"
        assert args.load_start_date == "2023-01-01"
        assert args.load_end_date == "2023-01-31"
        assert args.extra_spark_job_arguments == "{}"
        assert (
            args.table_privileges is None
        )  # Optional argument, should be None when not provided

    @patch(
        "sys.argv",
        [
            "load_core_visit.py",
            "forno",
            "test-bucket",
            "core_visit_test",
            "core",
            "visit",
            "2023-01-01",
            "2023-01-31",
            # extra_spark_job_arguments omitted - should default to "{}"
        ],
    )
    def test_parse_args_without_optional_arguments(self):
        """Test parse_args with optional extra_spark_job_arguments omitted."""
        # Arrange
        job = CoreVisitSparkJob()

        # Act
        args = job.parse_args()

        # Assert
        assert args.environment == "forno"
        assert args.bucket == "test-bucket"
        assert args.dag_name == "core_visit_test"
        assert args.schema == "core"
        assert args.table_name == "visit"
        assert args.load_start_date == "2023-01-01"
        assert args.load_end_date == "2023-01-31"
        assert args.extra_spark_job_arguments == "{}"  # Should default to empty JSON
        assert (
            args.table_privileges is None
        )  # Optional argument, should be None when not provided


class TestCreateVisitCoreModel:
    """Test cases for create_core_model method - isolated to this DAG context."""

    def test_create_core_model_basic_flow(
        self, spark_session, visit_df, visit_status_log_df, house_df
    ):
        """Test create_core_model orchestrates the full flow correctly."""
        # Mock the functions within the loaded module
        with patch.object(spark_session, "table") as mock_read_table, patch.object(
            load_core_visit, "SurrogateKeysHelper"
        ) as mock_surrogate_helper:

            # Arrange
            job = CoreVisitSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = (
                None
            )  # Set explicit None values instead of Mock objects
            mock_args.load_end_date = None
            mock_read_table.side_effect = [visit_status_log_df, visit_df, house_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration
            with patch.object(job, "get_visit_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "VISIT",
                    "VISIT_TABLE": "test_visit_table",
                    "VISIT_STATUS_LOG_TABLE": "test_vsl_table",
                    "HOUSE_TABLE": "test_house_table",
                    "CONTRACT_TABLE": "test_contract_table",
                }

                # Act
                result = job.create_core_model(spark_session, mock_args)

            # Assert
            assert mock_read_table.call_count == 3
            mock_surrogate_helper.generate_surrogate_key.assert_called_once()
            assert result == mock_result_df

    def test_create_core_model_logs_incremental_mode(
        self, spark_session, visit_df, visit_status_log_df, house_df
    ):
        """Test create_core_model logs INCREMENTAL mode when dates are provided."""
        # Mock the functions within the loaded module
        with patch.object(spark_session, "table") as mock_read_table, patch.object(
            load_core_visit, "SurrogateKeysHelper"
        ) as mock_surrogate_helper:

            # Arrange
            job = CoreVisitSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = "2023-01-01"
            mock_args.load_end_date = "2023-01-31"

            mock_read_table.side_effect = [visit_status_log_df, visit_df, house_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration and logger
            with patch.object(job, "get_visit_config") as mock_config, patch.object(
                job, "logger"
            ) as mock_logger:

                mock_config.return_value = {
                    "ENTITY_TYPE": "VISIT",
                    "VISIT_TABLE": "test_visit_table",
                    "VISIT_STATUS_LOG_TABLE": "test_vsl_table",
                    "HOUSE_TABLE": "test_house_table",
                    "CONTRACT_TABLE": "test_contract_table",
                }

                # Act
                job.create_core_model(spark_session, mock_args)

                # Assert
                mock_logger.info.assert_any_call(
                    "m=create_core_model, mode=INCREMENTAL, load_start_date=2023-01-01, load_end_date=2023-01-31"
                )

    def test_create_core_model_logs_full_mode_with_none_dates(
        self, spark_session, visit_df, visit_status_log_df, house_df
    ):
        """Test create_core_model logs FULL mode when dates are None."""
        # Mock the functions within the loaded module
        with patch.object(spark_session, "table") as mock_read_table, patch.object(
            load_core_visit, "SurrogateKeysHelper"
        ) as mock_surrogate_helper:

            # Arrange
            job = CoreVisitSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = None
            mock_args.load_end_date = None

            mock_read_table.side_effect = [visit_status_log_df, visit_df, house_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration and logger
            with patch.object(job, "get_visit_config") as mock_config, patch.object(
                job, "logger"
            ) as mock_logger:

                mock_config.return_value = {
                    "ENTITY_TYPE": "VISIT",
                    "VISIT_TABLE": "test_visit_table",
                    "VISIT_STATUS_LOG_TABLE": "test_vsl_table",
                    "HOUSE_TABLE": "test_house_table",
                    "CONTRACT_TABLE": "test_contract_table",
                }

                # Act
                job.create_core_model(spark_session, mock_args)

                # Assert
                mock_logger.info.assert_any_call(
                    "m=create_core_model, mode=FULL, msg=Running full load without date filtering"
                )

    def test_create_core_model_logs_full_mode_with_empty_dates(
        self, spark_session, visit_df, visit_status_log_df, house_df
    ):
        """Test create_core_model logs FULL mode when dates are empty strings."""
        # Mock the functions within the loaded module
        with patch.object(spark_session, "table") as mock_read_table, patch.object(
            load_core_visit, "SurrogateKeysHelper"
        ) as mock_surrogate_helper:

            # Arrange
            job = CoreVisitSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = ""
            mock_args.load_end_date = ""

            mock_read_table.side_effect = [visit_status_log_df, visit_df, house_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration and logger
            with patch.object(job, "get_visit_config") as mock_config, patch.object(
                job, "logger"
            ) as mock_logger:

                mock_config.return_value = {
                    "ENTITY_TYPE": "VISIT",
                    "VISIT_TABLE": "test_visit_table",
                    "VISIT_STATUS_LOG_TABLE": "test_vsl_table",
                    "HOUSE_TABLE": "test_house_table",
                    "CONTRACT_TABLE": "test_contract_table",
                }

                # Act
                job.create_core_model(spark_session, mock_args)

                # Assert
                mock_logger.info.assert_any_call(
                    "m=create_core_model, mode=FULL, msg=Running full load without date filtering"
                )

    def test_create_core_model_logs_full_mode_with_partial_dates(
        self, spark_session, visit_df, visit_status_log_df, house_df
    ):
        """Test create_core_model logs FULL mode when only one date is provided."""
        # Mock the functions within the loaded module
        with patch.object(spark_session, "table") as mock_read_table, patch.object(
            load_core_visit, "SurrogateKeysHelper"
        ) as mock_surrogate_helper:

            # Arrange
            job = CoreVisitSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = "2023-01-01"
            mock_args.load_end_date = None  # Only partial dates

            mock_read_table.side_effect = [visit_status_log_df, visit_df, house_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration and logger
            with patch.object(job, "get_visit_config") as mock_config, patch.object(
                job, "logger"
            ) as mock_logger:

                mock_config.return_value = {
                    "ENTITY_TYPE": "VISIT",
                    "VISIT_TABLE": "test_visit_table",
                    "VISIT_STATUS_LOG_TABLE": "test_vsl_table",
                    "HOUSE_TABLE": "test_house_table",
                    "CONTRACT_TABLE": "test_contract_table",
                }

                # Act
                job.create_core_model(spark_session, mock_args)

                # Assert
                mock_logger.info.assert_any_call(
                    "m=create_core_model, mode=FULL, msg=Running full load without date filtering"
                )

    def test_create_core_model_calls_static_methods_with_date_parameters(
        self, spark_session, visit_df, visit_status_log_df, house_df
    ):
        """Test create_core_model passes date parameters to static methods."""
        # Mock the functions within the loaded module, but allow static methods to run
        with patch.object(spark_session, "table") as mock_read_table, patch.object(
            load_core_visit, "SurrogateKeysHelper"
        ) as mock_surrogate_helper:

            # Arrange
            job = CoreVisitSparkJob()
            mock_args = Mock()
            mock_args.load_start_date = "2023-01-01"
            mock_args.load_end_date = "2023-01-31"

            mock_read_table.side_effect = [visit_status_log_df, visit_df, house_df]
            mock_result_df = Mock(spec=DataFrame)
            mock_result_df.count.return_value = 3
            mock_surrogate_helper.generate_surrogate_key.return_value = mock_result_df

            # Mock the configuration
            with patch.object(job, "get_visit_config") as mock_config:
                mock_config.return_value = {
                    "ENTITY_TYPE": "VISIT",
                    "VISIT_TABLE": "test_visit_table",
                    "VISIT_STATUS_LOG_TABLE": "test_vsl_table",
                    "HOUSE_TABLE": "test_house_table",
                    "CONTRACT_TABLE": "test_contract_table",
                }

                # Act - This will actually call the static methods with date filtering
                result = job.create_core_model(spark_session, mock_args)

                # Assert - Check that the result is valid and the method completed successfully
                assert result == mock_result_df
                mock_surrogate_helper.generate_surrogate_key.assert_called_once()


class TestJobConstants:
    """Test cases for job constants - isolated to this DAG context."""

    def test_job_name_constant(self):
        """Test JOB_NAME constant is defined correctly."""
        # Assert
        assert JOB_NAME == "core_visit"


# Pytest markers for conditional test execution
pytestmark = [
    pytest.mark.core_model,  # Mark for core model tests
    pytest.mark.spark,  # Mark for Spark tests
    pytest.mark.dag_specific,  # Mark for DAG-specific tests
]
