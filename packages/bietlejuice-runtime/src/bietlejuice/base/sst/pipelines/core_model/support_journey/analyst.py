from typing import Any, Dict, Optional

from pyspark.sql import SparkSession
from pyspark.sql import functions as F

from bietlejuice.base.core_models.helpers.schema_validator import (
    SchemaValidationError,
    SchemaValidator,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.sst.core.observability.metrics import save_scd_change_metric
from bietlejuice.base.sst.core.observability.sensors import partition_has_data
from bietlejuice.base.sst.core.quality.checks import validate_non_nullable_columns
from bietlejuice.base.sst.core.utils.common import (
    _complete_dataframe_schema,
    _table_exists,
    default_args,
    normalize_column_name,
    safe_union_with_target_schema,
)
from bietlejuice.base.sst.core.utils.time import standard_now, standardize_timestamps
from bietlejuice.base.sst.core.utils.transforms import (
    get_rows_to_update,
    get_versioning_df,
)
from bietlejuice.base.sst.domains.salesforce.common.transforms import (
    filter_relevant_cdc_events,
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
            "(e.g. core/core_support_journey/tables/analyst.yml)."
        ),
    ),
]


class SupportJourneyAnalystCoreModelPipeline(BaseCoreModelSparkJob):
    """
    Core model pipeline for support journey analysts (Salesforce User CDC events).
    Table-specific settings are loaded from ``tables/*.yml`` on S3 via
    ``--table_config_relative_path``. CLI flags match ``parse_parameters`` from the
    Airflow DAG (env, dag_name, bucket, partition_*, target_*, job_name,
    table_config_relative_path).
    """

    def __init__(self, cfg: Any) -> None:
        super().__init__(cfg.job_name)
        self.cfg = cfg
        self.table_spec: Optional[Dict[str, Any]] = None
        # tracked_cols: updated columns in CDC events, keyed by source table.
        # changed_field is non-normalized, so values are original Salesforce names.
        self.tracked_cols: Dict[str, Any] = {}

    def run_config(self):
        self.initialize_configuration(self.cfg.dag_name)
        self.table_spec = table_spec_from_cfg(self.cfg)
        self.spark = self.initialize_spark_session()

        sources = self.table_spec["sources"]
        for table, value in sources.items():
            tracked_cols = value.get("tracked_cols", None)
            if tracked_cols:
                self.logger.info(
                    f"m=create_core_model, msg=Adding tracked cols for {table=}"
                )
                self.tracked_cols[table] = tracked_cols

    def create_core_model(self, spark: SparkSession) -> None:
        """
        This method is used to create the core model dataframe.
        """
        sources = self.table_spec["sources"]

        user_src = sources["user"]
        target_full_table_name = (
            f"{self.table_spec['target_schema']}.{self.table_spec['target_table']}"
        )
        target_table_location = (
            f"s3a://{self.cfg.bucket}/{LayerEnum.CORE.value}/"
            f"{self.table_spec['target_schema']}/"
        )

        # schema_spec carries the full SchemaValidator contract (columns +
        # min_columns/max_columns/strict); expected_schema is just the columns.
        schema_spec = self.table_spec["schema"]
        expected_schema = schema_spec["columns"]
        schema_column_names = list(expected_schema.keys())

        if not self.table_spec.get("is_backfill_run", False):
            # Checking if the partition already exists in the target table
            if partition_has_data(
                spark,
                target_full_table_name,
                self.cfg.partition_date,
                self.cfg.partition_hour,
            ):
                self.logger.info(
                    f"m=create_core_model, msg=Partition {self.cfg.partition_date} "
                    f"{self.cfg.partition_hour} already exists in "
                    f"{target_full_table_name}"
                )
                return

            # Regular hourly run: process only the target partition (date + hour).
            self.logger.info(
                "m=create_core_model, msg=Hourly run: filtering single partition "
                f"partition_date={self.cfg.partition_date}, "
                f"partition_hour={self.cfg.partition_hour}"
            )
            hourly_filter_condition = (
                F.col("partition_date") == self.cfg.partition_date
            ) & (F.col("partition_hour") == self.cfg.partition_hour)
        else:
            # Backfill run: reprocess everything from the target partition forward.
            # Keep the predicate as plain comparisons on the raw partition columns
            # (no concat/expressions) so the metastore can prune partitions instead
            # of scanning the whole table history.
            self.logger.info(
                "m=create_core_model, msg=Backfill run: filtering all partitions "
                f">= partition_date={self.cfg.partition_date}, "
                f"partition_hour={self.cfg.partition_hour}"
            )
            hourly_filter_condition = (
                F.col("partition_date") > self.cfg.partition_date
            ) | (
                (F.col("partition_date") == self.cfg.partition_date)
                & (F.col("partition_hour") >= self.cfg.partition_hour)
            )

        # Reading the main source table and filtering by the partition
        self.logger.info(
            f"m=create_core_model, msg=Reading source table {user_src['table_name']}"
        )
        source_user_df = (
            spark.read.table(user_src["table_name"])
            .where(hourly_filter_condition)
            .select(*user_src["cols"])
        )

        tracked_cols = self.tracked_cols["user"]
        normalized_tracked = [normalize_column_name(col) for col in tracked_cols]
        self.logger.info(
            f"m=create_core_model, msg=Filtering CDC events by tracked cols: "
            f"{tracked_cols}"
        )
        relevant_events_df = filter_relevant_cdc_events(source_user_df, tracked_cols)

        # Emptiness is checked before dropDuplicates: the dedup shuffle cannot turn
        # a non-empty dataframe into an empty one, and skipping it here makes this
        # first action (the source scan) much cheaper.
        self.logger.info(
            "m=create_core_model, msg=Counting relevant CDC events "
            "(first Spark action: triggers the source scan)"
        )
        relevant_events_count = relevant_events_df.count()
        if relevant_events_count == 0:
            self.logger.warning(
                f"No user rows found in {user_src['table_name']} for partition "
                f"(partition_date={self.cfg.partition_date}, "
                f"partition_hour={self.cfg.partition_hour})"
            )
            return
        self.logger.info(
            f"m=create_core_model, msg=Found {relevant_events_count} relevant CDC "
            f"events; deduplicating by {normalized_tracked}"
        )
        filtered_user_df = relevant_events_df.dropDuplicates(normalized_tracked)

        # Creating the analyst dataframe with the necessary columns
        self.logger.info(
            "m=create_core_model, msg=Building analyst dataframe "
            "(id_analyst, id_type, id_event, is_deleted, renames, audit cols)"
        )
        now = standard_now(is_col=True)
        target_df = (
            filtered_user_df.withColumn("id_analyst", F.col("id_record"))
            .withColumn("id_type", F.lit("salesforce"))
            # committed_at is part of the hash because recovered/replayed CDC
            # events carry default transaction_key + commit_number, which would
            # collide distinct events for the same record.
            .withColumn(
                "id_event",
                F.sha2(
                    F.concat_ws(
                        "&",
                        F.col("id_record"),
                        F.col("transaction_key"),
                        F.col("commit_number"),
                        F.col("committed_at"),
                    ),
                    256,
                ),
            )
            .withColumn(
                "id_event_type",
                F.concat_ws(
                    "&",
                    F.lit("id_record"),
                    F.lit("transaction_key"),
                    F.lit("commit_number"),
                    F.lit("committed_at"),
                ),
            )
            .withColumn(
                "is_deleted",
                F.when(F.col("event_type") == "DELETE", F.lit(True)).otherwise(
                    F.lit(False)
                ),
            )
            .withColumn("bpo", F.col("bpo__c"))
            .withColumn("operations", F.col("operations__c"))
            # The CDC clean layer delivers IsPartner as a string ("true"/"false"),
            # while the schema contract declares it boolean. Cast explicitly so
            # schema validation passes regardless of the source column type.
            .withColumn("is_partner", F.col("is_partner").cast("boolean"))
            .withColumn("_created_at", now)
            .withColumn("_updated_at", now)
            .withColumn("_ts_load", now)
        )

        # SCD context is the immutable source-system id (id_type says which
        # system); cross-source joins downstream happen on email.
        context_col = "id_analyst"
        event_ts_col = "committed_at"
        commit_col = "commit_number"

        # commit_col is a versioning tiebreaker only: it must survive the union
        # projection so get_versioning_df can order by it, but it is not part of
        # the final table schema (dropped by the post-versioning select).
        # committed_at (event_ts_col) is persisted, same pattern as cases.
        union_column_names = schema_column_names + [commit_col]

        # Getting and updating the historical data
        if _table_exists(spark, target_full_table_name):
            self.logger.info(
                f"m=get_rows_to_update, msg=Getting the last current version from "
                f"{target_full_table_name} to update."
            )
            rows_to_update_df = get_rows_to_update(
                spark, target_full_table_name, target_df, context_col
            )
            unioned_target_df = safe_union_with_target_schema(
                target_df, rows_to_update_df, union_column_names
            )
            self.logger.info(
                "m=get_versioning_df, msg=The updated df was generated with success."
            )
        else:
            self.logger.info(
                f"m=get_versioning_df, msg=Is the first version for "
                f"{target_full_table_name}. Generating df to create table."
            )
            unioned_target_df = _complete_dataframe_schema(
                target_df, union_column_names
            )

        # Adding the versioning columns to the analyst dataframe
        self.logger.info(
            f"m=get_versioning_df, msg=Getting versioning dataframe for {context_col}"
        )
        self.logger.info(
            f"m=get_versioning_df, msg=Event timestamp column name: {event_ts_col}"
        )
        self.logger.info(
            f"m=get_versioning_df, msg=Commit number column name: {commit_col}"
        )

        versioned_df = get_versioning_df(
            unioned_target_df, context_col, event_ts_col, commit_col
        ).select(*schema_column_names)

        # Validating the schema of the dataframe
        self.logger.info("m=create_core_model, msg=Validating schema of the dataframe")
        validator = SchemaValidator()

        if validator.validate_schema(versioned_df, schema_spec):
            self.logger.info(
                "m=create_core_model, msg=Schema validation completed successfully"
            )
        else:
            raise SchemaValidationError("Schema validation failed")

        # Data-level null check for columns declared is_nullable: false
        self.logger.info("m=create_core_model, msg=Validating non-nullable columns")
        validate_non_nullable_columns(versioned_df, expected_schema)

        # Creating the pipeline to load the dataframe into the target table
        self.logger.info(
            "m=create_core_model, msg=Creating pipeline to load the dataframe "
            "into the target table"
        )

        versioned_df = standardize_timestamps(versioned_df, ["created_date"])

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

        self.logger.info("m=create_core_model, msg=Saving SCD change metric")
        save_scd_change_metric(
            spark=spark,
            df=versioned_df,
            bucket=self.cfg.bucket,
            metric_name="scd_type2_volume",
            target_table=target_full_table_name,
            partition_date=self.cfg.partition_date,
            partition_hour=self.cfg.partition_hour,
            env=self.cfg.env,
            layer=LayerEnum.CORE.value,
        )
        self.logger.info("m=create_core_model, msg=SCD change metric saved")

    def run(self) -> None:
        self.logger.info(f"m=run, msg=Starting {self.job_name} processing")
        self.logger.info(f"m=run, msg=Config: {self.cfg=}")
        self.run_config()
        self.create_core_model(self.spark)
        self.logger.info(
            f"m=run, msg={self.job_name} processing completed successfully"
        )


@default_args(optional_args=_DEFAULT_CLI_OPTIONAL_ARGS)
def main(cfg: Any) -> None:
    SupportJourneyAnalystCoreModelPipeline(cfg).run()


if __name__ == "__main__":
    main()
