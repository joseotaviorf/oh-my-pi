from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Optional

from pyspark.sql import DataFrame, SparkSession
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

    def _partition_cols_from_cdc(self, ts_cdc_col: str) -> List:
        return [
            F.date_format(F.col(ts_cdc_col), "yyyy-MM-dd").alias("partition_date"),
            F.date_format(F.col(ts_cdc_col), "HH").alias("partition_hour"),
        ]

    def build_ts_filter(
        self,
        partition_date: str,
        delta_hours: int = -80,
        col: Optional[str] = None,
    ):
        """
        Build a half-open timestamp filter on ``col`` anchored at
        ``partition_date`` 00:00 UTC and extended by signed ``delta_hours``.

        The window is bounded by the anchor (``partition_date`` 00:00 UTC) and
        the anchor shifted by ``delta_hours``. A negative ``delta_hours`` places
        the window before the anchor; a positive one places it after. The lower
        bound is inclusive and the upper bound is exclusive
        (``min_ts <= col < max_ts``).

        Examples
        --------
        delta_hours = 80:
            min_ts = partition_date 00:00
            max_ts = partition_date 00:00 + 80h

        delta_hours = -80:
            min_ts = partition_date 00:00 - 80h
            max_ts = partition_date 00:00
        """
        partition = datetime.strptime(partition_date, "%Y-%m-%d").replace(
            tzinfo=timezone.utc
        )
        delta_partition = partition + timedelta(hours=delta_hours)

        min_dt = min(partition, delta_partition)
        max_dt = max(partition, delta_partition)

        min_ts = min_dt.isoformat(timespec="milliseconds")
        max_ts = max_dt.isoformat(timespec="milliseconds")

        return (F.col(col) >= F.lit(min_ts)) & (F.col(col) < F.lit(max_ts))

    def _build_call_events_df(
        self,
        spark: SparkSession,
        session_df: DataFrame,
        bigfone_table: str,
    ) -> DataFrame:
        # For workflow_name == IVR Events -> URA, we don't have a direction, so we're settign it to inbound
        # For inbound calls, we're using id_call as id_task_call
        # For outbound calls, we're using id_task as id_task_call

        direction_cond = F.when(
            F.col("workflow_name") == F.lit("IVR Events"), F.lit("inbound")
        ).otherwise(F.col("direction"))
        call_event_df = (
            spark.table(bigfone_table)
            .where(
                self.build_ts_filter(
                    self.cfg.partition_date, delta_hours=-24, col="ts_cdc_transaction"
                )
            )
            .withColumn("direction", direction_cond)
            .where(F.col("id_call").isNotNull() | F.col("id_task").isNotNull())
            .select(
                F.col("id").alias("id_task_event"),
                "id_task",
                "id_call",
                "id_reservation",
                "id_worker",
                "direction",
                "channel_type",
                F.get_json_object("tags", "$.contact_subject_tag").alias("theme"),
                F.get_json_object("tags", "$.contact_subject_detail_tag").alias(
                    "theme_detail"
                ),
                F.get_json_object("tags", "$.journey_step_tag").alias(
                    "journey_step_tag"
                ),
                F.get_json_object("tags", "$.customer_type_tag").alias(
                    "customer_type_tag"
                ),
                F.get_json_object("tags", "$.contact_reason_tag").alias(
                    "contact_reason_tag"
                ),
                "bpo_name",
                "queue_name",
                "worker_email",
                "from_phone_number",
                "task_cancelation_reason",
                "to_phone_number",
                "waiting_time_sec",
                "ts_created",
                "ts_received",
                F.col("ts_cdc_transaction").alias("ts_updated"),
            )
        )

        final_call_df = (
            call_event_df.join(
                session_df,
                (F.col("id_task") == F.col("source_identity"))
                | (F.col("id_call") == F.col("source_identity")),
                how="inner",
            )
            .select(
                "id_task_event",
                "id_session",
                "id_support_session",
                "id_user",
                "database_source",
                "id_task",
                "id_reservation",
                "id_call",
                "id_worker",
                F.col("source").alias("service_type"),
                "theme",
                "theme_detail",
                "journey_step_tag",
                "customer_type_tag",
                "contact_reason_tag",
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
                F.col("ts_updated").alias("ts_task_updated"),
            )
            .withColumn("dedup_ts", F.col("ts_task_updated"))
        )

        return get_latest_version_from_df(
            final_call_df, ["id_task_event"], final_call_df.columns, ["dedup_ts"]
        )

    def _build_chats_results_df(
        self,
        spark: SparkSession,
        session_df: DataFrame,
        qm_channel_table: str,
        qm_chat_table: str,
        qm_task_table: str,
        qm_task_event_table: str,
    ) -> DataFrame:

        chat_filter = self.build_ts_filter(
            self.cfg.partition_date, delta_hours=-72, col="ts_updated"
        )

        # A task can be routed through more than one queue, so we keep the queue_name from
        # the most recent event per task (latest ts_updated) and left-join it
        # onto the task events further down. This mirrors the enrich chats query
        # (ROW_NUMBER() OVER (PARTITION BY id_task ORDER BY ts_updated DESC) = 1).
        queue_lookup_df = get_latest_version_from_df(
            spark.table(qm_task_event_table)
            .where(chat_filter)
            .where(F.col("queue_name").isNotNull())
            .select("id_task", "queue_name", "ts_updated"),
            ["id_task"],
            ["queue_name"],
            "ts_updated",
        ).alias("q")

        channel = spark.table(qm_channel_table).where(chat_filter)
        chat_session = session_df.where(F.col("source") == F.lit("chat")).withColumn(
            "join_key",
            F.when(
                F.col("database_source") == "sauron",
                F.coalesce(F.col("id_session"), F.col("id_support_session")),
            ).otherwise(F.col("id_support_session")),
        )

        whatsapp_chats_df = (
            channel.alias("c")
            .join(
                chat_session.alias("s"),
                on=["id_session"],
                how="left",
            )
            .select(
                F.lit(None).alias("id_chat"),
                F.col("c.id_channel"),
                F.col("c.id_session"),
                F.col("s.id_support_session"),
                F.lit(None).alias("channel_type"),
                F.col("s.id_user"),
                F.col("s.user_phone"),
                F.col("s.user_email"),
                F.col("s.created_by"),
                F.col("s.source"),
                F.col("s.source_environment"),
                F.col("s.database_source"),
            )
        )

        chat = spark.table(qm_chat_table).where(chat_filter).alias("c")

        inapp_sessions = chat.join(
            chat_session.alias("session"),
            on=F.col("session.join_key") == F.col("c.id_session"),
            how="inner",
        ).select(
            F.col("c.id_chat"),
            F.lit(None).alias("id_channel"),
            F.col("c.id_session"),
            F.col("session.id_support_session"),
            F.json_tuple(F.col("c.attributes"), "channel_type").alias("channel_type"),
            F.col("session.id_user").alias("id_user"),
            F.col("session.user_phone").alias("user_phone"),
            F.col("session.user_email").alias("user_email"),
            F.col("session.created_by").alias("created_by"),
            F.col("session.source").alias("source"),
            F.col("session.source_environment").alias("source_environment"),
            F.col("session.database_source").alias("database_source"),
        )

        task_df = (
            spark.table(qm_task_table)
            .where(
                self.build_ts_filter(
                    self.cfg.partition_date, delta_hours=-24, col="ts_updated"
                )
            )
            .withColumn("dedup_ts", F.col("ts_updated"))
            .alias("c")
        )
        task_cols = task_df.columns
        task_df = get_latest_version_from_df(task_df, ["id"], task_cols, ["dedup_ts"])

        task_events_df = task_df.select(
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
            F.get_json_object("tags", "$.contact_subject_tag").alias("theme"),
            F.get_json_object("tags", "$.contact_subject_detail_tag").alias(
                "theme_detail"
            ),
            F.get_json_object("tags", "$.journey_step_tag").alias("journey_step_tag"),
            F.get_json_object("tags", "$.customer_type_tag").alias("customer_type_tag"),
            F.get_json_object("tags", "$.contact_reason_tag").alias(
                "contact_reason_tag"
            ),
            "channel_status",
            "bpo_name",
            "bpo_selection_reason",
            "assigned_to",
            "seconds_to_first_response",
            "is_forwarded",
            "is_per_team_task",
            "is_spoc_task",
            "ts_cdc_transaction",
            "task_attributes",
            "id_source_ctwa",
            "url_source_ctwa",
            "type_source_ctwa",
            "total_inactivity_time",
            "last_inactivity_time",
            "ts_created",
            "ts_updated",
        ).alias("t")

        ias = inapp_sessions.alias("ias")
        ws = whatsapp_chats_df.alias("ws")

        union_ias_ws = ias.unionByName(ws, allowMissingColumns=True)

        # Resolve the inbound/outbound direction for chat service events.
        # created_by = 'hsm_sent' marks a company-initiated WhatsApp HSM
        # (template) message and is always outbound, regardless of whether the
        # task is a SPOC task — otherwise these events fall through to the
        # inbound default and are misclassified.
        is_spoc_task_col = F.col("t.is_spoc_task")
        created_by_col = F.coalesce(F.col("u.created_by"))
        chat_direction_cond = (
            F.when(created_by_col == "hsm_sent", F.lit("outbound"))
            .when(
                is_spoc_task_col & (created_by_col == "human_support"),
                F.lit("inbound"),
            )
            .when(
                is_spoc_task_col & (created_by_col == "user"),
                F.lit("outbound"),
            )
            .otherwise(F.lit("inbound"))
        )

        final_chat_df = (
            task_events_df.alias("t")
            .join(
                union_ias_ws.alias("u"),
                on=(
                    (F.col("u.id_chat") == F.col("t.id_chat"))
                    | (F.col("u.id_channel") == F.col("t.id_channel"))
                ),
                how="inner",
            )
            .join(
                queue_lookup_df,
                on=F.col("q.id_task") == F.col("t.id_task"),
                how="left",
            )
            .where(F.col("u.id_session").isNotNull())
            .select(
                F.col("t.id_task_event"),
                F.col("t.id_channel"),
                F.col("t.id_task"),
                F.col("u.id_session").cast("string").alias("id_session"),
                F.col("u.id_support_session").alias("id_support_session"),
                F.col("u.id_user").alias("id_user"),
                F.col("t.id_worker"),
                F.col("t.id_source_ctwa"),
                F.col("u.database_source").alias("database_source"),
                F.lit("chat").alias("service_type"),
                F.coalesce(F.col("u.user_email"), F.col("t.customer_email")).alias(
                    "customer_email"
                ),
                F.coalesce(F.col("u.user_phone"), F.col("t.from_phone_number")).alias(
                    "customer_phone_number"
                ),
                F.col("t.twilio_phone_number"),
                F.when(F.col("u.source") == "internal_chat", F.lit("in app"))
                .otherwise(F.col("u.source"))
                .alias("origin"),
                chat_direction_cond.alias("direction"),
                F.col("t.worker_email"),
                F.col("t.channel_type"),
                F.col("t.task_status"),
                F.col("t.task_outcome"),
                F.col("t.task_completion_reason"),
                F.col("t.theme"),
                F.col("t.theme_detail"),
                F.col("t.journey_step_tag"),
                F.col("t.customer_type_tag"),
                F.col("t.contact_reason_tag"),
                F.col("t.bpo_name"),
                F.col("t.bpo_selection_reason"),
                F.col("q.queue_name"),
                F.col("t.seconds_to_first_response"),
                F.col("t.is_forwarded"),
                F.col("t.is_per_team_task"),
                F.col("t.is_spoc_task"),
                F.when(
                    F.col("u.source_environment").isin(
                        "isaias_inbound", "isaias_inbound_main"
                    ),
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
            )
        ).withColumn("dedup_ts", F.col("ts_task_updated"))

        return get_latest_version_from_df(
            final_chat_df, ["id_task_event"], final_chat_df.columns, ["dedup_ts"]
        )

    def _build_target_df(
        self,
        spark: SparkSession,
        sources: Dict[str, Any],
    ) -> DataFrame:

        CALL_SOURCES = ["call_in_app", "call"]
        CHAT_SOURCES = ["internal_chat", "whatsapp"]
        source_cond = (
            F.when(F.col("source").isin(CALL_SOURCES), F.lit("call"))
            .when(F.col("source").isin(CHAT_SOURCES), F.lit("chat"))
            .otherwise(F.lit(None))
        )
        ts_filter = self.build_ts_filter(
            self.cfg.partition_date, delta_hours=-72, col="ts_updated"
        )

        sss_source_df = spark.table(sources["support_session"]["table_name"]).where(
            F.col("ts_created").isNotNull()
        )

        sss_base_df = (
            sss_source_df.where(F.col("ts_created").isNotNull())
            .where(ts_filter)
            .select(
                F.col("id").cast("string").alias("id_session"),
                F.col("public_id").alias("id_support_session"),
                source_cond.alias("source"),
                F.json_tuple(F.col("user_data"), "user_id").alias("id_user"),
                F.json_tuple(F.col("user_data"), "user_phone").alias("user_phone"),
                F.json_tuple(F.col("user_data"), "user_email").alias("user_email"),
                F.col("created_by"),
                F.col("source_env").alias("source_environment"),
                F.col("source_identity"),
                F.lit("support_session_service").alias("database_source"),
            )
        )

        sauron_source_df = spark.table(sources["sauron_session"]["table_name"])
        sauron_base_df = (
            sauron_source_df.where(ts_filter)
            .select(
                F.col("id").cast("string").alias("id_session"),
                F.col("public_id").alias("id_support_session"),
                source_cond.alias("source"),
                F.json_tuple(F.col("user_data"), "user_id").alias("id_user"),
                F.json_tuple(F.col("user_data"), "user_phone").alias("user_phone"),
                F.json_tuple(F.col("user_data"), "user_email").alias("user_email"),
                F.col("created_by"),
                F.col("source_environment"),
                F.col("source_identity"),
                F.lit("sauron").alias("database_source"),
                F.col("ts_created"),
            )
            .where(
                (
                    (F.col("source") == "call")
                    & (F.col("ts_created") < F.lit("2025-11-10 00:00:00"))
                )
                | (F.col("source") == "chat")
            )
            .drop("ts_created")
        )

        session_df = (sauron_base_df.union(sss_base_df)).persist()

        call_events_df = self._build_call_events_df(
            spark,
            session_df,
            sources["bigfone_event"]["table_name"],
        )
        chats_results_df = self._build_chats_results_df(
            spark,
            session_df,
            sources["qm_channel"]["table_name"],
            sources["qm_chat"]["table_name"],
            sources["qm_task"]["table_name"],
            sources["qm_task_event"]["table_name"],
        )
        partition_date, partition_hour = self._partition_cols_from_cdc(
            "ts_task_updated"
        )
        return (
            call_events_df.unionByName(chats_results_df, allowMissingColumns=True)
            .withColumn(
                "id_event",
                F.sha2(
                    F.concat_ws(
                        "_",
                        F.col("id_session"),
                        F.col("id_support_session"),
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
                    F.lit("id_support_session"),
                    F.lit("id_task"),
                    F.lit("id_task_event"),
                ),
            )
            .withColumn("partition_date", partition_date)
            .withColumn("partition_hour", partition_hour)
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

        previous_partition_date = (
            datetime.strptime(self.cfg.partition_date, "%Y-%m-%d") - timedelta(hours=24)
        ).strftime("%Y-%m-%d")

        if partition_has_data(
            spark,
            target_full_table_name,
            previous_partition_date,
            None,
        ):
            self.logger.info(
                "m=create_core_model, "
                f"msg=Partition {self.cfg.partition_date} already exists in "
                f"{target_full_table_name}"
            )
            return

        bigfone_events_df = spark.table(sources["bigfone_event"]["table_name"]).where(
            self.build_ts_filter(
                self.cfg.partition_date,
                delta_hours=-24,
                col="ts_cdc_transaction",
            )
        )
        qm_tasks_df = spark.table(sources["qm_task"]["table_name"]).where(
            self.build_ts_filter(
                self.cfg.partition_date, delta_hours=-24, col="ts_updated"
            )
        )

        if bigfone_events_df.isEmpty() and qm_tasks_df.isEmpty():
            raise ValueError(
                "No service event rows found in "
                f"{sources['bigfone_event']['table_name']} or "
                f"{sources['qm_task']['table_name']} for partition "
                f"partition_date={self.cfg.partition_date}"
            )

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
