from typing import Any

from pyspark.sql import SparkSession
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
        name="table_config_json",
        flags=["--table_config_json"],
        type=str,
        required=True,
        help="JSON string of tables/<table>.yml (merge keys, sources, schema, etc.).",
    ),
]


class SupportJourneyCoreModelPipeline(BaseCoreModelSparkJob):
    """
    Core model pipeline for support journey entities. Table-specific settings are
    passed at runtime via ``--table_config_json`` (serialized YAML from DAG ``tables/*.yml``).
    CLI flags match ``parse_parameters`` from the Airflow DAG (env, dag_name, bucket,
    partition_*, target_*, job_name, table_config_json).
    """

    def __init__(self, cfg: Any) -> None:
        super().__init__(cfg.job_name)
        self.cfg = cfg
        self.table_spec = table_spec_from_cfg(cfg)

    def create_core_model(self, spark: SparkSession) -> None:
        """
        This method is used to create the core model dataframe.
        """
        sources = self.table_spec["sources"]

        case_src = sources["case"]
        target_full_table_name = (
            f"{self.table_spec['target_schema']}.{self.table_spec['target_table']}"
        )
        target_table_location = f"s3a://{self.cfg.bucket}/{LayerEnum.CORE.value}/{self.table_spec['target_schema']}/"

        expected_schema = self.table_spec["schema"]["columns"]
        schema_column_names = list(expected_schema.keys())

        # Checking if the partition already exists in the target table
        if partition_has_data(
            spark,
            target_full_table_name,
            self.cfg.partition_date,
            self.cfg.partition_hour,
        ):
            self.logger.info(
                f"m=create_core_model, msg=Partition {self.cfg.partition_date} {self.cfg.partition_hour} already exists in {target_full_table_name}"
            )
            return

        # Reading the main source table and filtering by the partition
        source_case_df = spark.table(case_src["table_name"]).where(
            (F.col("partition_date") == self.cfg.partition_date)
            & (F.col("partition_hour") == self.cfg.partition_hour)
        )

        # Checking if the source table is empty - if it is, we raise an error
        if source_case_df.isEmpty():
            self.logger.warning(
                f"No case rows found in {case_src['table_name']} for partition "
                f"(partition_date={self.cfg.partition_date}, partition_hour={self.cfg.partition_hour})"
            )
            return

        # Creating the case dataframe with the necessary columns
        source_case_mandatory_columns_df = (
            source_case_df.withColumn("id_case", F.col("id_record"))
            .withColumn(
                "id_event",
                F.sha2(
                    F.concat_ws(
                        "_",
                        F.col("id_record"),
                        F.col("transaction_key"),
                        F.col("commit_number"),
                    ),
                    256,
                ),
            )
            .withColumn(
                "bk_case_event",
                F.concat_ws(
                    "_",
                    F.lit("id_record"),
                    F.lit("transaction_key"),
                    F.lit("commit_number"),
                ),
            )
            .withColumn(
                "is_deleted",
                F.when(F.col("event_type") == "DELETE", F.lit(True)).otherwise(
                    F.lit(False)
                ),
            )
            .withColumn("_created_at", F.now())
            .withColumn("_updated_at", F.now())
            .withColumn("_ts_load", F.now())
        )

        # Reading and handling the secondary source tables
        record_types_src = sources["record_types"]
        case_milestones_src = sources["case_milestones"]

        source_record_types_df = spark.table(record_types_src["table_name"])
        source_case_milestones_df = spark.table(case_milestones_src["table_name"])

        source_latest_record_types_df = get_latest_version_from_df(
            source_record_types_df,
            record_types_src["key_cols"],
            record_types_src["cols"],
            record_types_src["sort_col"],
        )

        source_latest_case_milestones_df = get_latest_version_from_df(
            source_case_milestones_df,
            case_milestones_src["key_cols"],
            case_milestones_src["cols"],
            case_milestones_src["sort_col"],
        )

        # Joining the dataframes and selecting the necessary columns
        target_df = (
            source_case_mandatory_columns_df.alias("cv")
            .join(
                source_latest_record_types_df.alias("lrt"),
                on=["id_record_type"],
                how="left",
            )
            .join(
                source_latest_case_milestones_df.alias("lcm"),
                on=["id_case"],
                how="left",
            )
            .select(
                "cv.*",
                *[f"lrt.{c}" for c in record_types_src["cols"]],
                *[f"lcm.{c}" for c in case_milestones_src["cols"]],
            )
        )

        context_col = "id_case"
        event_col = "event_type"
        event_ts_col = "committed_at"
        commit_col = "commit_number"

        # Getting and updating the historical data
        if _table_exists(spark, target_full_table_name):
            self.logger.info(
                f"m=get_rows_to_update, msg=Getting the last current version from {target_full_table_name} to update."
            )
            rows_to_update_df = get_rows_to_update(
                spark, target_full_table_name, target_df, context_col
            )
            unioned_target_df = safe_union_with_target_schema(
                target_df, rows_to_update_df, schema_column_names
            )
            self.logger.info(
                "m=get_versioning_df, msg=The updated df was generated with success."
            )
        else:
            self.logger.info(
                f"m=get_versioning_df, msg=Is the first version for {target_full_table_name}. Generating df to create table."
            )
            unioned_target_df = _complete_dataframe_schema(
                target_df, schema_column_names
            )

        # Adding the versioning columns to the case dataframe
        self.logger.info(
            f"m=get_versioning_df, msg=Getting versioning dataframe for {context_col}"
        )
        self.logger.info(f"m=get_versioning_df, msg=Event column name: {event_col}")
        self.logger.info(
            f"m=get_versioning_df, msg=Event timestamp column name: {event_ts_col}"
        )
        self.logger.info(
            f"m=get_versioning_df, msg=Commit number column name: {commit_col}"
        )

        versioned_df = get_versioning_df(
            unioned_target_df, context_col, event_col, event_ts_col, commit_col
        ).select(*schema_column_names)

        # Validating the schema of the dataframe
        self.logger.info("m=create_core_model, msg=Validating schema of the dataframe")
        validator = SchemaValidator()

        if validator.validate_schema(versioned_df, expected_schema):
            self.logger.info(
                "m=create_core_model, msg=Schema validation completed successfully"
            )
        else:
            raise SchemaValidationError("Schema validation failed")

        # Creating the pipeline to load the dataframe into the target table
        self.logger.info(
            "m=create_core_model, msg=Creating pipeline to load the dataframe into the target table"
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
        self.spark = self.initialize_spark_session()
        self.create_core_model(self.spark)
        self.logger.info(
            f"m=run, msg={self.job_name} processing completed successfully"
        )


@default_args(optional_args=_DEFAULT_CLI_OPTIONAL_ARGS)
def main(cfg: Any) -> None:
    SupportJourneyCoreModelPipeline(cfg).run()


if __name__ == "__main__":
    main()
