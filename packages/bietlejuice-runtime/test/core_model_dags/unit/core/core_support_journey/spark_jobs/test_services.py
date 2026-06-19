"""Unit tests for SupportJourneyServicesCoreModelPipeline (services table)."""

import json
from datetime import datetime, timedelta
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import pytest
import yaml
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    BooleanType,
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.core_models.helpers.schema_validator import SchemaValidationError
from bietlejuice.base.sst.domains.salesforce.core_models.config_loader import (
    table_spec_from_cfg,
)
from bietlejuice.base.sst.pipelines.core_model.support_journey import (
    services as services_module,
)


def _find_project_root() -> Path:
    current = Path(__file__).resolve().parent
    while current != current.parent:
        if (current / ".git").exists():
            return current
        current = current.parent
    raise RuntimeError("Could not locate project root from test path")


@pytest.fixture
def table_spec():
    spec_path = (
        _find_project_root() / "dags/core/core_support_journey/tables/services.yml"
    )
    return yaml.safe_load(spec_path.read_text(encoding="utf-8"))


@pytest.fixture
def cfg(table_spec):
    return SimpleNamespace(
        job_name="load_core_support_journey_services",
        dag_name="core_support_journey",
        partition_date="2026-05-27",
        partition_hour="14",
        bucket="test-bucket",
        table_config_json=json.dumps(table_spec),
    )


@pytest.fixture
def pipeline_with_spec(cfg, table_spec):
    pipeline = services_module.SupportJourneyServicesCoreModelPipeline(cfg)
    pipeline.table_spec = table_spec_from_cfg(cfg)
    return pipeline


class TestSupportJourneyServicesCoreModelPipelineInit:
    def test_table_spec_loaded_from_json_string(self, cfg, table_spec):
        spec = table_spec_from_cfg(cfg)

        assert spec["target_table"] == table_spec["target_table"]
        assert spec["merge_on"] == table_spec["merge_on"]

    def test_table_spec_accepts_dict_config(self, table_spec):
        cfg = SimpleNamespace(
            job_name="load_core_support_journey_services",
            dag_name="core_support_journey",
            partition_date="2026-05-27",
            partition_hour="14",
            bucket="test-bucket",
            table_config_json=table_spec,
        )

        assert table_spec_from_cfg(cfg) == table_spec

    @mock.patch(
        "bietlejuice.base.sst.domains.salesforce.core_models.config_loader.load_table_spec_from_relative_path"
    )
    def test_table_spec_loaded_from_relative_path(self, mock_load, table_spec):
        mock_load.return_value = table_spec
        cfg = SimpleNamespace(
            table_config_relative_path="core/core_support_journey/tables/services.yml"
        )

        assert table_spec_from_cfg(cfg) == table_spec
        mock_load.assert_called_once_with(
            "core/core_support_journey/tables/services.yml"
        )


class TestSupportJourneyServicesBuildTsFilter:
    @pytest.mark.parametrize(
        "partition_date, delta_hours, expected_min, expected_max",
        [
            # build_ts_filter anchors the window at partition_date 00:00 UTC and
            # shifts it by signed delta_hours. A negative delta places the
            # half-open window before the anchor (processing whole prior days);
            # a positive delta places it after.
            (
                "2026-05-27",
                -24,
                "2026-05-26T00:00:00.000+00:00",
                "2026-05-27T00:00:00.000+00:00",
            ),
            (
                "2026-05-27",
                -72,
                "2026-05-24T00:00:00.000+00:00",
                "2026-05-27T00:00:00.000+00:00",
            ),
            (
                "2026-05-27",
                80,
                "2026-05-27T00:00:00.000+00:00",
                "2026-05-30T08:00:00.000+00:00",
            ),
        ],
    )
    def test_window_bounds(
        self,
        pipeline_with_spec,
        partition_date,
        delta_hours,
        expected_min,
        expected_max,
    ):
        # act
        ts_filter = pipeline_with_spec.build_ts_filter(
            partition_date, delta_hours=delta_hours, col="ts_event"
        )

        # assert: build_ts_filter returns a half-open Spark filter
        # (min_ts <= col < max_ts); the literal bounds are rendered in the
        # Column expression string.
        filter_str = str(ts_filter)
        assert expected_min in filter_str
        assert expected_max in filter_str

    def test_negative_delta_processes_previous_day(self, pipeline_with_spec):
        # act
        ts_filter = pipeline_with_spec.build_ts_filter(
            "2026-05-27", delta_hours=-24, col="ts_event"
        )

        # assert: a -24h delta yields the full previous day window,
        # [previous_day 00:00, partition_date 00:00).
        filter_str = str(ts_filter)
        assert "2026-05-26T00:00:00.000+00:00" in filter_str
        assert "2026-05-27T00:00:00.000+00:00" in filter_str


class TestSupportJourneyServicesCoreModelPipelineCreateCoreModel:
    @mock.patch.object(services_module, "partition_has_data")
    def test_skips_when_partition_already_exists(
        self, mock_partition_has_data, cfg, pipeline_with_spec
    ):
        # arrange
        spark = mock.MagicMock()
        mock_partition_has_data.return_value = True
        pipeline = pipeline_with_spec

        # act
        pipeline.create_core_model(spark)

        # assert: the existence check is anchored on the previous partition
        # day (partition_date - 24h), not on partition_date itself.
        previous_partition_date = (
            datetime.strptime(cfg.partition_date, "%Y-%m-%d") - timedelta(hours=24)
        ).strftime("%Y-%m-%d")
        mock_partition_has_data.assert_called_once_with(
            spark,
            "core_support_journey.services",
            previous_partition_date,
            None,
        )
        spark.table.assert_not_called()

    @mock.patch.object(services_module, "partition_has_data")
    def test_raises_when_event_sources_are_empty(
        self, mock_partition_has_data, cfg, pipeline_with_spec
    ):
        # arrange
        spark = mock.MagicMock()
        empty_df = mock.MagicMock()
        empty_df.isEmpty.return_value = True
        table_df = mock.MagicMock()
        table_df.where.return_value = empty_df
        spark.table.return_value = table_df
        mock_partition_has_data.return_value = False
        pipeline = pipeline_with_spec

        # act / assert
        with pytest.raises(ValueError, match="No service event rows found"):
            pipeline.create_core_model(spark)

        assert spark.table.call_count == 2
        empty_df.isEmpty.assert_called()

    @mock.patch.object(services_module, "DataFrameDeltaTableLoaderPipeline")
    @mock.patch.object(services_module, "SchemaValidator")
    @mock.patch.object(services_module, "get_versioning_df")
    @mock.patch.object(services_module, "_complete_dataframe_schema")
    @mock.patch.object(services_module, "_table_exists")
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline, "_build_target_df"
    )
    @mock.patch.object(services_module, "partition_has_data")
    def test_runs_delta_pipeline_when_schema_is_valid(
        self,
        mock_partition_has_data,
        mock_build_target_df,
        mock_table_exists,
        mock_complete_schema,
        mock_get_versioning_df,
        mock_schema_validator_cls,
        mock_pipeline_cls,
        cfg,
        pipeline_with_spec,
    ):
        # arrange
        mock_partition_has_data.return_value = False
        mock_table_exists.return_value = False

        non_empty_df = mock.MagicMock()
        non_empty_df.isEmpty.return_value = False
        table_df = mock.MagicMock()
        table_df.where.return_value = non_empty_df
        spark = mock.MagicMock()
        spark.table.return_value = table_df

        target_df = mock.MagicMock()
        mock_build_target_df.return_value = target_df

        versioned_df = mock.MagicMock()
        versioned_df.select.return_value = versioned_df
        mock_get_versioning_df.return_value = versioned_df
        mock_complete_schema.return_value = target_df

        validator = mock_schema_validator_cls.return_value
        validator.validate_schema.return_value = True

        mock_pipeline = mock_pipeline_cls.return_value
        pipeline = pipeline_with_spec

        # act
        pipeline.create_core_model(spark)

        # assert
        mock_build_target_df.assert_called_once()
        mock_pipeline_cls.assert_called_once()
        mock_pipeline.run.assert_called_once()

    @mock.patch.object(services_module, "SchemaValidator")
    @mock.patch.object(services_module, "get_versioning_df")
    @mock.patch.object(services_module, "_complete_dataframe_schema")
    @mock.patch.object(services_module, "_table_exists")
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline, "_build_target_df"
    )
    @mock.patch.object(services_module, "partition_has_data")
    def test_raises_when_schema_validation_fails(
        self,
        mock_partition_has_data,
        mock_build_target_df,
        mock_table_exists,
        mock_complete_schema,
        mock_get_versioning_df,
        mock_schema_validator_cls,
        cfg,
        pipeline_with_spec,
    ):
        # arrange
        mock_partition_has_data.return_value = False
        mock_table_exists.return_value = False

        non_empty_df = mock.MagicMock()
        non_empty_df.isEmpty.return_value = False
        table_df = mock.MagicMock()
        table_df.where.return_value = non_empty_df
        spark = mock.MagicMock()
        spark.table.return_value = table_df

        target_df = mock.MagicMock()
        mock_build_target_df.return_value = target_df

        versioned_df = mock.MagicMock()
        versioned_df.select.return_value = versioned_df
        mock_get_versioning_df.return_value = versioned_df
        mock_complete_schema.return_value = target_df

        validator = mock_schema_validator_cls.return_value
        validator.validate_schema.return_value = False

        pipeline = pipeline_with_spec

        # act / assert
        with pytest.raises(SchemaValidationError, match="Schema validation failed"):
            pipeline.create_core_model(spark)


class TestSupportJourneyServicesCoreModelPipelineRun:
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline, "create_core_model"
    )
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline,
        "initialize_spark_session",
    )
    @mock.patch.object(
        services_module.SupportJourneyServicesCoreModelPipeline,
        "initialize_configuration",
    )
    @mock.patch.object(services_module, "table_spec_from_cfg")
    def test_run_initializes_spark_and_executes_pipeline(
        self,
        mock_table_spec_from_cfg,
        mock_initialize_configuration,
        mock_initialize_spark_session,
        mock_create_core_model,
        cfg,
        table_spec,
    ):
        # arrange
        spark = mock.MagicMock()
        mock_initialize_spark_session.return_value = spark
        mock_table_spec_from_cfg.return_value = table_spec
        pipeline = services_module.SupportJourneyServicesCoreModelPipeline(cfg)

        # act
        pipeline.run()

        # assert
        mock_initialize_configuration.assert_called_once_with(cfg.dag_name)
        mock_table_spec_from_cfg.assert_called_once_with(cfg)
        mock_initialize_spark_session.assert_called_once()
        mock_create_core_model.assert_called_once_with(spark)


@pytest.fixture(scope="session")
def spark_session():
    spark = (
        SparkSession.builder.appName("SupportJourneyServicesTest")
        .config("spark.sql.warehouse.dir", "/tmp/spark-warehouse")
        .config("spark.sql.adaptive.enabled", "false")
        .config("spark.sql.adaptive.coalescePartitions.enabled", "false")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield spark
    spark.stop()


# Empty source schemas for the chat branches that are irrelevant to the queue
# attribution scenario (WhatsApp channels). _build_chats_results_df still reads
# them, so they must exist with the columns the method projects.
_CHANNEL_SCHEMA = StructType(
    [
        StructField("id_channel", StringType(), True),
        StructField("id_session", StringType(), True),
        StructField("ts_updated", TimestampType(), True),
    ]
)

_TASK_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("id_channel", StringType(), True),
        StructField("id_chat", StringType(), True),
        StructField("id_task", StringType(), True),
        StructField("id_worker", StringType(), True),
        StructField("worker_email", StringType(), True),
        StructField("channel_type", StringType(), True),
        StructField("customer_phone_number", StringType(), True),
        StructField("customer_contact_info", StringType(), True),
        StructField("twilio_phone_number", StringType(), True),
        StructField("customer_email", StringType(), True),
        StructField("task_status", StringType(), True),
        StructField("task_outcome", StringType(), True),
        StructField("completion_reason", StringType(), True),
        StructField("tags", StringType(), True),
        StructField("channel_status", StringType(), True),
        StructField("bpo_name", StringType(), True),
        StructField("bpo_selection_reason", StringType(), True),
        StructField("assigned_to", StringType(), True),
        StructField("seconds_to_first_response", LongType(), True),
        StructField("is_forwarded", BooleanType(), True),
        StructField("is_per_team_task", BooleanType(), True),
        StructField("is_spoc_task", BooleanType(), True),
        StructField("ts_cdc_transaction", TimestampType(), True),
        StructField("task_attributes", StringType(), True),
        StructField("id_source_ctwa", StringType(), True),
        StructField("url_source_ctwa", StringType(), True),
        StructField("type_source_ctwa", StringType(), True),
        StructField("total_inactivity_time", LongType(), True),
        StructField("last_inactivity_time", LongType(), True),
        StructField("ts_created", TimestampType(), True),
        StructField("ts_updated", TimestampType(), True),
    ]
)

_CHAT_SCHEMA = StructType(
    [
        StructField("id_chat", StringType(), True),
        StructField("id_session", StringType(), True),
        StructField("attributes", StringType(), True),
        StructField("ts_updated", TimestampType(), True),
    ]
)

_SESSION_SCHEMA = StructType(
    [
        StructField("id_session", StringType(), True),
        StructField("id_support_session", StringType(), True),
        StructField("source", StringType(), True),
        StructField("id_user", StringType(), True),
        StructField("user_phone", StringType(), True),
        StructField("user_email", StringType(), True),
        StructField("created_by", StringType(), True),
        StructField("source_environment", StringType(), True),
        StructField("database_source", StringType(), True),
    ]
)

_TASK_EVENT_SCHEMA = StructType(
    [
        StructField("id_task", StringType(), True),
        StructField("queue_name", StringType(), True),
        StructField("ts_updated", TimestampType(), True),
    ]
)


class TestSupportJourneyServicesQueueAttribution:
    """Regression coverage for the chat routing-queue resolution.

    Pins the bug where queue_lookup_df collapsed task_event rows with
    F.max(queue_name) (alphabetically greatest) instead of taking the queue
    from the most recent event (latest ts_updated), matching the enrich chats
    query ROW_NUMBER() OVER (PARTITION BY id_task ORDER BY ts_updated DESC) = 1.
    """

    def _build_chats(self, spark, pipeline_with_spec, task_event_rows):
        session_df = spark.createDataFrame(
            [
                (
                    "S1",  # id_session
                    "SS1",  # id_support_session
                    "chat",  # source
                    "U1",  # id_user
                    None,  # user_phone
                    "customer@example.com",  # user_email
                    "user",  # created_by
                    "isaias_inbound",  # source_environment
                    "support_session_service",  # database_source
                ),
            ],
            _SESSION_SCHEMA,
        )
        channel_df = spark.createDataFrame([], _CHANNEL_SCHEMA)
        chat_df = spark.createDataFrame(
            [
                (
                    "C1",  # id_chat
                    "SS1",  # id_session (matches session join_key)
                    '{"channel_type": "web"}',  # attributes
                    datetime(2026, 5, 26, 9, 0, 0),  # ts_updated
                ),
            ],
            _CHAT_SCHEMA,
        )
        task_df = spark.createDataFrame(
            [
                (
                    "EV1",  # id (id_task_event)
                    None,  # id_channel
                    "C1",  # id_chat
                    "T1",  # id_task
                    "W1",  # id_worker
                    "worker@example.com",  # worker_email
                    "web",  # channel_type
                    None,  # customer_phone_number
                    None,  # customer_contact_info
                    None,  # twilio_phone_number
                    "customer@example.com",  # customer_email
                    "completed",  # task_status
                    None,  # task_outcome
                    None,  # completion_reason
                    None,  # tags
                    None,  # channel_status
                    None,  # bpo_name
                    None,  # bpo_selection_reason
                    None,  # assigned_to
                    10,  # seconds_to_first_response
                    False,  # is_forwarded
                    False,  # is_per_team_task
                    False,  # is_spoc_task
                    datetime(2026, 5, 26, 12, 0, 0),  # ts_cdc_transaction
                    None,  # task_attributes
                    None,  # id_source_ctwa
                    None,  # url_source_ctwa
                    None,  # type_source_ctwa
                    0,  # total_inactivity_time
                    0,  # last_inactivity_time
                    datetime(2026, 5, 26, 8, 0, 0),  # ts_created
                    datetime(2026, 5, 26, 12, 0, 0),  # ts_updated
                ),
            ],
            _TASK_SCHEMA,
        )
        task_event_df = spark.createDataFrame(task_event_rows, _TASK_EVENT_SCHEMA)

        table_map = {
            "qm_channel": channel_df,
            "qm_chat": chat_df,
            "qm_task": task_df,
            "qm_task_event": task_event_df,
        }
        spark_stub = mock.MagicMock()
        spark_stub.table.side_effect = lambda name: table_map[name]

        return pipeline_with_spec._build_chats_results_df(
            spark_stub,
            session_df,
            "qm_channel",
            "qm_chat",
            "qm_task",
            "qm_task_event",
        )

    def test_resolves_queue_from_most_recent_event(
        self, spark_session, pipeline_with_spec
    ):
        # arrange: the alphabetically greatest queue ("zeta_queue") is the
        # OLDER event; the most recent event routes to "alpha_queue".
        task_event_rows = [
            ("T1", "zeta_queue", datetime(2026, 5, 25, 10, 0, 0)),
            ("T1", "alpha_queue", datetime(2026, 5, 26, 10, 0, 0)),
        ]

        # act
        result = self._build_chats(spark_session, pipeline_with_spec, task_event_rows)
        rows = result.where("id_task = 'T1'").select("queue_name").collect()

        # assert
        assert len(rows) == 1
        assert rows[0]["queue_name"] == "alpha_queue"

    def test_ignores_null_queue_on_latest_event(
        self, spark_session, pipeline_with_spec
    ):
        # arrange: the newest event has a NULL queue_name and must be skipped;
        # the latest NON-null queue wins. The skipped older event also carries
        # the alphabetically greatest name, so F.max would mis-attribute it.
        task_event_rows = [
            ("T1", "zeta_queue", datetime(2026, 5, 25, 10, 0, 0)),
            ("T1", "alpha_queue", datetime(2026, 5, 26, 10, 0, 0)),
            ("T1", None, datetime(2026, 5, 26, 23, 0, 0)),
        ]

        # act
        result = self._build_chats(spark_session, pipeline_with_spec, task_event_rows)
        rows = result.where("id_task = 'T1'").select("queue_name").collect()

        # assert
        assert len(rows) == 1
        assert rows[0]["queue_name"] == "alpha_queue"
