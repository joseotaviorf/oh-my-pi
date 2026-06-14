from typing import Any, Dict, List, Optional

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F

from bietlejuice.base.core_models.helpers.schema_validator import (
    SchemaValidationError,
    SchemaValidator,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.sst.core.observability.sensors import partition_has_data
from bietlejuice.base.sst.core.utils.common import (
    _complete_dataframe_schema,
    _table_exists,
    default_args,
    get_latest_version_from_df,
    safe_union_with_target_schema,
)
from bietlejuice.base.sst.core.utils.time import standard_now, standardize_timestamps
from bietlejuice.base.sst.core.utils.transforms import (
    get_rows_to_update,
    get_versioning_df,
)
from bietlejuice.base.sst.domains.salesforce.core_models.config_loader import (
    table_spec_from_cfg,
)
from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)

_DEFAULT_CLI_OPTIONAL_ARGS = [
    dict(
        name="dag_name",
        flags=["--dag_name", "--dag-name"],
        type=str,
        required=True,
        help="DAG name (ConfigurationService source), e.g. core_support_journey.",
    ),
    dict(
        name="partition_date",
        flags=["--partition_date", "--partition-date"],
        type=str,
        required=True,
        help="Partition date (YYYY-MM-DD); set by DAG data_interval_start.",
    ),
    dict(
        name="partition_hour",
        flags=["--partition_hour", "--partition-hour"],
        type=str,
        required=True,
        help="Partition hour (HH); set by DAG data_interval_start.",
    ),
    dict(
        name="bucket",
        flags=["--bucket"],
        type=str,
        required=True,
        help="Datalake S3 bucket; same as DAG BASE_PARAMETERS bucket.",
    ),
    dict(
        name="table_config_relative_path",
        flags=["--table_config_relative_path"],
        type=str,
        required=True,
        help=(
            "Path relative to astronomer/dags on artifacts S3 "
            "(e.g. core/core_support_journey/tables/services.yml)."
        ),
    ),
]

_VERSIONING_CONTEXT_COLS = ["id_session", "id_task"]
_VERSIONING_EVENT_TS_COL = "ts_task_updated"
_TIMESTAMP_COLS = [
    "ts_task_created",
    "ts_task_updated",
    "ts_session_event_created",
    "ts_session_event_updated",
    "ts_session_created",
    "ts_session_updated",
    "_effective_timestamp",
    "_expired_timestamp",
]


class SupportJourneyServicesCoreModelPipeline(BaseCoreModelSparkJob):
    """
    Core model pipeline for support journey service events (calls and chats).
    Table-specific settings are loaded from ``tables/*.yml`` on S3 via
    ``--table_config_relative_path``.
    """

    def __init__(self, cfg: Any) -> None:
        super().__init__(cfg.job_name)
        self.cfg = cfg
        self.table_spec: Optional[Dict[str, Any]] = None

    def _event_partition_filter(self, df: DataFrame) -> DataFrame:
        """Filter CDC event sources by transaction date (daily upstream DAGs)."""
        return df.where(
            F.to_date(F.col("ts_cdc_transaction")) == F.lit(self.cfg.partition_date)
        )

    def _partition_cols_from_cdc(self, ts_cdc_col: str) -> List:
        return [
            F.date_format(F.to_date(F.col(ts_cdc_col)), "yyyy-MM-dd").alias(
                "partition_date"
            ),
            F.hour(F.col(ts_cdc_col)).cast("string").alias("partition_hour"),
        ]

    def _build_call_events_df(
        self,
        spark: SparkSession,
        sss_source_df: DataFrame,
        sauron_source_df: DataFrame,
        bigfone_table: str,
    ) -> DataFrame:
        calls_sauron_df = (
            sauron_source_df.where(F.col("source").isin("call_in_app", "call"))
            .withColumn("id_sauron_session", F.col("id"))
            .withColumn("id_session_event", F.lit(None))
            .withColumn("id_user", F.json_tuple(F.col("user_data"), "user_id"))
            .withColumn("id_support_session", F.col("public_id"))
            .withColumn("database_source", F.lit("sauron"))
            .select(
                "id_sauron_session",
                "id_session_event",
                "id_user",
                "id_support_session",
                "source_identity",
                "database_source",
                F.col("ts_created").alias("ts_session_event_created"),
                F.col("ts_updated").alias("ts_session_event_updated"),
                F.min("ts_created")
                .over(Window.partitionBy("id"))
                .alias("ts_session_created"),
                F.max("ts_updated")
                .over(Window.partitionBy("id"))
                .alias("ts_session_updated"),
            )
        )

        calls_sss_df = (
            sss_source_df.where(F.col("source").isin("call_in_app", "call"))
            .withColumn("id_sauron_session", F.lit(None))
            .withColumn("id_session_event", F.col("id"))
            .withColumn("id_user", F.json_tuple(F.col("user_data"), "user_id"))
            .withColumn("id_support_session", F.col("public_id"))
            .withColumn("database_source", F.lit("support_session_service"))
            .select(
                "id_sauron_session",
                "id_session_event",
                "id_user",
                "id_support_session",
                "source_identity",
                "database_source",
                F.col("ts_created").alias("ts_session_event_created"),
                F.col("ts_updated").alias("ts_session_event_updated"),
                F.min("ts_created")
                .over(Window.partitionBy("id"))
                .alias("ts_session_created"),
                F.max("ts_updated")
                .over(Window.partitionBy("id"))
                .alias("ts_session_updated"),
            )
        )

        cross_call_df = calls_sauron_df.union(calls_sss_df)

        call_events_source_df = self._event_partition_filter(
            spark.table(bigfone_table)
        ).withColumn("_dedup_sort_ts", F.col("ts_cdc_transaction"))
        call_cols = call_events_source_df.columns
        call_events_source_df = get_latest_version_from_df(
            call_events_source_df, ["id"], call_cols, ["_dedup_sort_ts"]
        )

        return (
            call_events_source_df.join(
                cross_call_df,
                on=(F.col("source_identity") == F.col("id_call"))
                | (F.col("source_identity") == F.col("id_task")),
                how="left",
            )
            .withColumn("id_task_event", F.col("id"))
            .withColumn(
                "id_session",
                F.coalesce(F.col("id_sauron_session"), F.col("id_session_event")),
            )
            .select(
                "id_support_session",
                "id_sauron_session",
                "id_session",
                "id_user",
                "database_source",
                "id_session_event",
                "id_task",
                "id_reservation",
                "id_call",
                "id_task_event",
                "id_worker",
                F.lit("call").alias("service_type"),
                "direction",
                "channel_type",
                "bpo_name",
                "queue_name",
                "worker_email",
                "from_phone_number",
                "task_cancelation_reason",
                "to_phone_number",
                "waiting_time_sec",
                F.col("ts_created").alias("ts_task_created"),
                F.col("ts_received").alias("ts_task_updated"),
                "ts_session_event_created",
                "ts_session_event_updated",
                "ts_session_created",
                "ts_session_updated",
                *self._partition_cols_from_cdc("ts_cdc_transaction"),
            )
            .filter(F.col("id_session").isNotNull())
        )

    def _build_chats_results_df(
        self,
        spark: SparkSession,
        sss_source_df: DataFrame,
        sauron_source_df: DataFrame,
        qm_channel_table: str,
        qm_chat_table: str,
        qm_task_table: str,
    ) -> DataFrame:
        sss_chats_df = (
            sss_source_df.where(F.col("source").isin(["internal_chat"]))
            .withColumn("database_source", F.lit("support_session"))
            .select(
                F.col("id").alias("id_session_event"),
                F.lit(None).alias("id_sauron_session"),
                F.col("public_id").alias("id_support_session"),
                F.json_tuple(F.col("user_data"), "user_id").alias("id_user"),
                F.json_tuple(F.col("user_data"), "user_phone").alias("user_phone"),
                F.json_tuple(F.col("user_data"), "user_email").alias("user_email"),
                "created_by",
                "source",
                F.col("source_env").alias("source_environment"),
                "database_source",
                F.col("ts_created").alias("ts_session_event_created"),
                F.col("ts_updated").alias("ts_session_event_updated"),
                F.min("ts_created")
                .over(Window.partitionBy("id"))
                .alias("ts_session_created"),
                F.max("ts_updated")
                .over(Window.partitionBy("id"))
                .alias("ts_session_updated"),
            )
        )

        sauron_chats_df = (
            sauron_source_df.where(F.col("source").isin(["internal_chat", "whatsapp"]))
            .withColumn("database_source", F.lit("sauron"))
            .withColumn(
                "id_session_event",
                F.sha2(
                    F.concat_ws("_", F.col("id"), F.col("ts_updated")),
                    256,
                ),
            )
            .select(
                "id_session_event",
                F.col("id").alias("id_sauron_session"),
                F.col("public_id").alias("id_support_session"),
                F.json_tuple(F.col("user_data"), "user_id").alias("id_user"),
                F.json_tuple(F.col("user_data"), "user_phone").alias("user_phone"),
                F.json_tuple(F.col("user_data"), "user_email").alias("user_email"),
                "created_by",
                "source",
                "source_environment",
                "database_source",
                F.col("ts_created").alias("ts_session_event_created"),
                F.col("ts_updated").alias("ts_session_event_updated"),
                F.min("ts_created")
                .over(Window.partitionBy("id"))
                .alias("ts_session_created"),
                F.max("ts_updated")
                .over(Window.partitionBy("id"))
                .alias("ts_session_updated"),
            )
        )

        channel = spark.table(qm_channel_table).alias("c")
        whatsapp_chats_df = channel.join(
            sauron_chats_df.alias("s"),
            on=F.col("s.id_sauron_session") == F.col("c.id_session"),
            how="left",
        ).select(
            F.col("c.id_channel"),
            F.col("c.id_session"),
            F.col("s.id_sauron_session"),
            F.col("s.id_support_session"),
            F.col("s.id_user"),
            F.col("s.user_phone"),
            F.col("s.user_email"),
            F.col("s.created_by"),
            F.col("s.source"),
            F.col("s.source_environment"),
            F.col("s.database_source"),
            F.col("s.ts_session_created"),
            F.col("s.ts_session_updated"),
            F.col("ts_session_event_created"),
            F.col("ts_session_event_updated"),
        )

        chat = spark.table(qm_chat_table).alias("c")
        inapp_sessions = (
            chat.join(
                sss_chats_df.alias("sss"),
                on=(F.col("sss.id_support_session") == F.col("c.id_session"))
                & (F.col("c.source").isin("support_session")),
                how="left",
            )
            .join(
                sauron_chats_df.alias("s"),
                on=(F.col("s.id_sauron_session") == F.col("c.id_session"))
                & (F.col("c.source").isin("sauron")),
                how="left",
            )
            .select(
                F.col("c.id_chat"),
                F.col("c.id_session"),
                F.col("s.id_sauron_session"),
                F.col("sss.id_support_session"),
                F.json_tuple(F.col("c.attributes"), "channel_type").alias(
                    "channel_type"
                ),
                F.coalesce(F.col("sss.id_user"), F.col("s.id_user")).alias("id_user"),
                F.coalesce(F.col("sss.user_phone"), F.col("s.user_phone")).alias(
                    "user_phone"
                ),
                F.coalesce(F.col("sss.user_email"), F.col("s.user_email")).alias(
                    "user_email"
                ),
                F.coalesce(F.col("sss.created_by"), F.col("s.created_by")).alias(
                    "created_by"
                ),
                F.coalesce(F.col("sss.source"), F.col("s.source")).alias("source"),
                F.coalesce(
                    F.col("sss.source_environment"), F.col("s.source_environment")
                ).alias("source_environment"),
                F.coalesce(
                    F.col("sss.database_source"), F.col("s.database_source")
                ).alias("database_source"),
                F.coalesce(
                    F.col("sss.ts_session_created"), F.col("s.ts_session_created")
                ).alias("ts_session_created"),
                F.coalesce(
                    F.col("sss.ts_session_updated"), F.col("s.ts_session_updated")
                ).alias("ts_session_updated"),
                F.coalesce(
                    F.col("sss.ts_session_event_created"),
                    F.col("s.ts_session_event_created"),
                ).alias("ts_session_event_created"),
                F.coalesce(
                    F.col("sss.ts_session_event_updated"),
                    F.col("s.ts_session_event_updated"),
                ).alias("ts_session_event_updated"),
            )
        )

        tasks_source_df = self._event_partition_filter(
            spark.table(qm_task_table)
        ).withColumn("_dedup_sort_ts", F.col("ts_cdc_transaction"))
        task_cols = tasks_source_df.columns
        tasks_source_df = get_latest_version_from_df(
            tasks_source_df, ["id"], task_cols, ["_dedup_sort_ts"]
        )

        task_events_df = tasks_source_df.select(
            F.col("id").alias("id_task_event"),
            "id_channel",
            "id_chat",
            "id_task",
            "id_worker",
            "worker_email",
            F.when(
                F.col("channel_type") == "whatsapp",
                F.coalesce(
                    F.col("customer_phone_number"),
                    F.regexp_replace(
                        F.col("customer_contact_info"), "whatsapp:\\+", ""
                    ),
                ),
            )
            .otherwise(F.lit(None))
            .alias("from_phone_number"),
            F.regexp_replace(F.col("twilio_phone_number"), "whatsapp:\\+", "").alias(
                "twilio_phone_number"
            ),
            "customer_email",
            "channel_type",
            "task_status",
            "task_outcome",
            F.col("completion_reason").alias("task_completion_reason"),
            "channel_status",
            "bpo_name",
            "bpo_selection_reason",
            "assigned_to",
            "seconds_to_first_response",
            "is_forwarded",
            "is_per_team_task",
            "is_spoc_task",
            "ts_created",
            "ts_updated",
            "ts_cdc_transaction",
            "task_attributes",
            "id_source_ctwa",
            "url_source_ctwa",
            "type_source_ctwa",
            "total_inactivity_time",
            "last_inactivity_time",
        ).alias("t")

        ias = inapp_sessions.alias("ias")
        ws = whatsapp_chats_df.alias("ws")

        return (
            task_events_df.join(
                ias, on=F.col("ias.id_chat") == F.col("t.id_chat"), how="left"
            )
            .join(ws, on=F.col("ws.id_channel") == F.col("t.id_channel"), how="left")
            .where(
                (
                    F.coalesce(
                        F.col("ias.id_session"), F.col("ws.id_session")
                    ).isNotNull()
                )
                & (
                    F.coalesce(
                        F.col("ias.ts_session_created"), F.col("ws.ts_session_created")
                    ).isNotNull()
                )
            )
            .select(
                F.col("t.id_task_event"),
                F.col("t.id_channel"),
                F.col("t.id_task"),
                F.coalesce(F.col("ias.id_session"), F.col("ws.id_session"))
                .cast("string")
                .alias("id_session"),
                F.coalesce(
                    F.col("ias.id_support_session"), F.col("ws.id_support_session")
                ).alias("id_support_session"),
                F.coalesce(
                    F.col("ias.id_sauron_session"), F.col("ws.id_sauron_session")
                ).alias("id_sauron_session"),
                F.coalesce(F.col("ias.id_user"), F.col("ws.id_user")).alias("id_user"),
                F.col("t.id_worker"),
                F.col("t.id_source_ctwa"),
                F.coalesce(
                    F.col("ias.database_source"), F.col("ws.database_source")
                ).alias("database_source"),
                F.lit("chat").alias("service_type"),
                F.coalesce(
                    F.col("ias.user_email"),
                    F.col("ws.user_email"),
                    F.col("t.customer_email"),
                ).alias("customer_email"),
                F.coalesce(
                    F.col("ias.user_phone"),
                    F.col("ws.user_phone"),
                    F.col("t.from_phone_number"),
                ).alias("customer_phone_number"),
                F.col("t.twilio_phone_number"),
                F.when(
                    F.coalesce(F.col("ias.source"), F.col("ws.source"))
                    == "internal_chat",
                    F.lit("in app"),
                )
                .otherwise(F.coalesce(F.col("ias.source"), F.col("ws.source")))
                .alias("origin"),
                F.when(
                    F.col("t.is_spoc_task")
                    & (
                        F.coalesce(F.col("ias.created_by"), F.col("ws.created_by"))
                        == "human_support"
                    ),
                    F.lit("inbound"),
                )
                .when(
                    F.col("t.is_spoc_task")
                    & (
                        F.coalesce(F.col("ias.created_by"), F.col("ws.created_by"))
                        == "user"
                    ),
                    F.lit("outbound"),
                )
                .otherwise(F.lit("inbound"))
                .alias("direction"),
                F.col("t.worker_email"),
                F.col("t.channel_type"),
                F.col("t.task_status"),
                F.col("t.task_outcome"),
                F.col("t.task_completion_reason"),
                F.col("t.bpo_name"),
                F.col("t.bpo_selection_reason"),
                F.col("t.seconds_to_first_response"),
                F.col("t.is_forwarded"),
                F.col("t.is_per_team_task"),
                F.col("t.is_spoc_task"),
                F.when(
                    F.coalesce(
                        F.col("ias.source_environment"), F.col("ws.source_environment")
                    ).isin("isaias_inbound", "isaias_inbound_main"),
                    F.lit(True),
                )
                .otherwise(F.lit(False))
                .alias("is_isaias_session"),
                F.col("t.url_source_ctwa"),
                F.col("t.type_source_ctwa"),
                F.col("t.total_inactivity_time"),
                F.col("t.last_inactivity_time"),
                F.col("t.ts_created").alias("ts_task_created"),
                F.col("t.ts_updated").alias("ts_task_updated"),
                F.col("t.task_attributes"),
                F.coalesce(
                    F.col("ias.ts_session_created"), F.col("ws.ts_session_created")
                ).alias("ts_session_created"),
                F.coalesce(
                    F.col("ias.ts_session_updated"), F.col("ws.ts_session_updated")
                ).alias("ts_session_updated"),
                F.coalesce(
                    F.col("ias.ts_session_event_created"),
                    F.col("ws.ts_session_event_created"),
                ).alias("ts_session_event_created"),
                F.coalesce(
                    F.col("ias.ts_session_event_updated"),
                    F.col("ws.ts_session_event_updated"),
                ).alias("ts_session_event_updated"),
                *self._partition_cols_from_cdc("t.ts_cdc_transaction"),
            )
        )

    def _build_target_df(
        self,
        spark: SparkSession,
        sources: Dict[str, Any],
    ) -> DataFrame:
        sss_source_df = spark.table(sources["support_session"]["table_name"]).where(
            F.col("ts_created").isNotNull()
        )
        sauron_source_df = spark.table(sources["sauron_session"]["table_name"])

        call_events_df = self._build_call_events_df(
            spark,
            sss_source_df,
            sauron_source_df,
            sources["bigfone_event"]["table_name"],
        )
        chats_results_df = self._build_chats_results_df(
            spark,
            sss_source_df,
            sauron_source_df,
            sources["qm_channel"]["table_name"],
            sources["qm_chat"]["table_name"],
            sources["qm_task"]["table_name"],
        )

        return (
            call_events_df.unionByName(chats_results_df, allowMissingColumns=True)
            .withColumn(
                "id_event",
                F.sha2(
                    F.concat_ws(
                        "_",
                        F.col("id_session"),
                        F.col("id_session_event"),
                        F.col("id_task"),
                        F.col("id_task_event"),
                    ),
                    256,
                ),
            )
            .withColumn(
                "id_event_type",
                F.concat_ws(
                    "_",
                    F.lit("id_session"),
                    F.lit("id_session_event"),
                    F.lit("id_task"),
                    F.lit("id_task_event"),
                ),
            )
            .withColumn("_created_at", standard_now(is_col=True))
            .withColumn("_ts_load", standard_now(is_col=True))
        )

    def create_core_model(self, spark: SparkSession) -> None:
        sources = self.table_spec["sources"]
        target_full_table_name = (
            f"{self.table_spec['target_schema']}.{self.table_spec['target_table']}"
        )
        target_table_location = (
            f"s3a://{self.cfg.bucket}/{LayerEnum.CORE.value}/"
            f"{self.table_spec['target_schema']}/"
        )

        expected_schema = self.table_spec["schema"]["columns"]
        schema_column_names = list(expected_schema.keys())

        if partition_has_data(
            spark,
            target_full_table_name,
            self.cfg.partition_date,
            None,
        ):
            self.logger.info(
                "m=create_core_model, "
                f"msg=Partition {self.cfg.partition_date} already exists in "
                f"{target_full_table_name}"
            )
            return

        bigfone_events_df = self._event_partition_filter(
            spark.table(sources["bigfone_event"]["table_name"])
        )
        qm_tasks_df = self._event_partition_filter(
            spark.table(sources["qm_task"]["table_name"])
        )

        if bigfone_events_df.isEmpty() and qm_tasks_df.isEmpty():
            self.logger.warning(
                "No service event rows found in "
                f"{sources['bigfone_event']['table_name']} or "
                f"{sources['qm_task']['table_name']} for partition "
                f"partition_date={self.cfg.partition_date})"
            )
            return

        target_df = self._build_target_df(spark, sources)

        if _table_exists(spark, target_full_table_name):
            self.logger.info(
                "m=get_rows_to_update, "
                f"msg=Getting the last current version from {target_full_table_name} "
                "to update."
            )
            rows_to_update_df = get_rows_to_update(
                spark,
                target_full_table_name,
                target_df,
                _VERSIONING_CONTEXT_COLS,
            )
            unioned_target_df = safe_union_with_target_schema(
                target_df, rows_to_update_df, schema_column_names
            )
            self.logger.info(
                "m=get_versioning_df, msg=The updated df was generated with success."
            )
        else:
            self.logger.info(
                "m=get_versioning_df, "
                f"msg=Is the first version for {target_full_table_name}. "
                "Generating df to create table."
            )
            unioned_target_df = _complete_dataframe_schema(
                target_df, schema_column_names
            )

        self.logger.info(
            "m=get_versioning_df, "
            f"msg=Getting versioning dataframe for {_VERSIONING_CONTEXT_COLS}"
        )
        self.logger.info(
            "m=get_versioning_df, "
            f"msg=Event timestamp column name: {_VERSIONING_EVENT_TS_COL}"
        )

        versioned_df = get_versioning_df(
            unioned_target_df,
            _VERSIONING_CONTEXT_COLS,
            _VERSIONING_EVENT_TS_COL,
        ).select(*schema_column_names)

        versioned_df = standardize_timestamps(versioned_df, _TIMESTAMP_COLS)

        self.logger.info("m=create_core_model, msg=Validating schema of the dataframe")
        validator = SchemaValidator()

        if validator.validate_schema(versioned_df, expected_schema):
            self.logger.info(
                "m=create_core_model, msg=Schema validation completed successfully"
            )
        else:
            raise SchemaValidationError("Schema validation failed")

        self.logger.info(
            "m=create_core_model, "
            "msg=Creating pipeline to load the dataframe into the target table"
        )
        pipeline = DataFrameDeltaTableLoaderPipeline(
            database_name=self.table_spec["target_schema"],
            table_name=self.table_spec["target_table"],
            database_location=target_table_location,
            layer=LayerEnum.CORE.value,
            dataframe=versioned_df,
            partitions=self.table_spec["partition_cols"],
            target_database_name=self.table_spec["target_schema"],
            target_database_location=target_table_location,
            merge_on=self.table_spec["merge_on"],
            when_matched_update_condition=self.table_spec.get(
                "when_matched_update_condition", None
            ),
            spark=spark,
        )

        self.logger.info(
            "m=create_core_model, msg=Running the delta table loader pipeline"
        )
        pipeline.run()
        self.logger.info(
            "m=run_pipeline, "
            f"msg=History loading completed for table={self.table_spec['target_table']}"
        )

    def run(self) -> None:
        self.logger.info(f"m=run, msg=Starting {self.job_name} processing")
        self.logger.info(f"m=run, msg=Config: {self.cfg=}")
        self.initialize_configuration(self.cfg.dag_name)
        self.table_spec = table_spec_from_cfg(self.cfg)
        self.spark = self.initialize_spark_session()
        self.create_core_model(self.spark)
        self.logger.info(
            f"m=run, msg={self.job_name} processing completed successfully"
        )


@default_args(optional_args=_DEFAULT_CLI_OPTIONAL_ARGS)
def main(cfg: Any) -> None:
    SupportJourneyServicesCoreModelPipeline(cfg).run()


if __name__ == "__main__":
    main()
