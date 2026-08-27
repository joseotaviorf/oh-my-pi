from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import (
    coalesce,
    col,
    current_timestamp,
    dayofmonth,
    lit,
    month,
    when,
    year,
)

from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob

JOB_NAME = "core_credit_evaluation"


class CoreCreditEvaluationSparkJob(BaseCoreModelSparkJob):
    """Core Credit Evaluation Spark job implementation."""

    def __init__(self):
        """Initialize the Core Credit Evaluation Spark job."""
        super().__init__(JOB_NAME)

    def get_credit_evaluation_config(self):
        """Get credit evaluation-specific configuration."""
        return {
            "ENTITY_TYPE": self.get_config("ENTITY_TYPE"),
            "CREDIT_EVALUATION_TABLE": self.get_config("CREDIT_EVALUATION_TABLE"),
            "HOUSE_TABLE": self.get_config("HOUSE_TABLE"),
            "HOUSE_LISTING_RELATION_TABLE": self.get_config(
                "HOUSE_LISTING_RELATION_TABLE"
            ),
            "EBDB_USER_TABLE": self.get_config("EBDB_USER_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core credit evaluation model from DocX data."""

        # Load configuration
        config = self.get_credit_evaluation_config()

        # Load source data
        credit_evaluation_df = self._load_credit_evaluation_data(spark, config, args)
        house_df = self._load_house_data(spark, config)
        house_listing_relation_df = self._load_house_listing_relation_data(
            spark, config
        )
        user_df = self._load_user_data(spark, config)

        # Join all data
        result_df = self._join_all_data(
            credit_evaluation_df, house_df, house_listing_relation_df, user_df
        )

        # Generate surrogate key
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            result_df, config["ENTITY_TYPE"], id_column="id_credit_evaluation"
        )
        result_df = result_df.withColumnRenamed(
            "surrogate_key", "sk_core_credit_evaluation"
        )

        # Add partitioning columns
        result_df = (
            result_df.withColumn("year", year(col("ts_updated")))
            .withColumn("month", month(col("ts_updated")))
            .withColumn("day", dayofmonth(col("ts_updated")))
        )

        return result_df

    def _load_credit_evaluation_data(self, spark, config, args):
        """Load and filter credit evaluation data."""
        credit_evaluation_df = spark.read.table(config["CREDIT_EVALUATION_TABLE"])

        # Apply date filter if provided (for incremental loads)
        if (
            args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        ):
            credit_evaluation_df = credit_evaluation_df.filter(
                (
                    col("ts_updated").cast("date")
                    >= lit(args.load_start_date).cast("date")
                )
                & (
                    col("ts_updated").cast("date")
                    <= lit(args.load_end_date).cast("date")
                )
            )

        return credit_evaluation_df

    def _load_house_data(self, spark, config):
        """Load house data."""
        return spark.read.table(config["HOUSE_TABLE"])

    def _load_house_listing_relation_data(self, spark, config):
        """Load house listing relation data."""
        return spark.read.table(config["HOUSE_LISTING_RELATION_TABLE"])

    def _load_user_data(self, spark, config):
        """Load user data."""
        return spark.read.table(config["EBDB_USER_TABLE"])

    def _resolve_property_owners(self, house_listing_relation_df, user_df):
        """Resolve PROPERTY_OWNER relations to user.id via two equi-joins.

        `id_related` holds either a numeric `user.id` or `user.uuid_person`. A single
        OR join across those columns forces BroadcastNestedLoopJoin on EMR.
        """
        hl = house_listing_relation_df.filter(col("related_as") == "PROPERTY_OWNER")

        owners_by_id = (
            hl.alias("hl")
            .join(
                user_df.alias("u"),
                col("u.id").cast("string") == col("hl.id_related"),
                "inner",
            )
            .select(col("hl.id").alias("id_house"), col("u.id").alias("id_owner"))
        )

        owners_by_uuid = (
            hl.alias("hl")
            .join(
                user_df.alias("u"),
                col("u.uuid_person") == col("hl.id_related"),
                "inner",
            )
            .select(col("hl.id").alias("id_house"), col("u.id").alias("id_owner"))
        )

        return owners_by_id.union(owners_by_uuid)

    def _join_all_data(
        self, credit_evaluation_df, house_df, house_listing_relation_df, user_df
    ):
        """Join all data sources to create the final result."""

        owner_resolved_df = self._resolve_property_owners(
            house_listing_relation_df, user_df
        )

        # Start with credit evaluation data
        result_df = credit_evaluation_df.alias("ce")

        # Join with house
        result_df = result_df.join(
            house_df.alias("h"), col("ce.id_house") == col("h.id"), "left"
        )

        result_df = result_df.join(
            owner_resolved_df.alias("owner"),
            col("ce.id_house") == col("owner.id_house"),
            "left",
        )

        # Select final columns with transformations
        return result_df.select(
            col("ce.id").alias("id_credit_evaluation"),
            col("ce.id_house"),
            col("ce.id_proposal"),
            col("ce.id_user"),
            coalesce(col("owner.id_owner"), col("h.id_user")).alias("id_owner"),
            col("ce.id_city"),
            col("ce.id_group"),
            col("ce.reason"),
            col("ce.result"),
            col("ce.early_result"),
            col("ce.limit_value"),
            col("ce.pre_approved_limit").alias("user_pre_approved_limit"),
            col("ce.status"),
            col("ce.type").alias("documentation_policy_type"),
            when(
                coalesce(col("ce.id_group"), col("ce.id_proposal")).isNull(), lit(True)
            )
            .otherwise(lit(False))
            .alias("is_early_credit"),
            when(col("ce.scope") == "CITY", lit(True))
            .otherwise(lit(False))
            .alias("is_credit_passport"),
            when(col("ce.result") == "BYPASSED", lit(True))
            .otherwise(lit(False))
            .alias("is_bypass"),
            col("ce.ts_created"),
            col("ce.ts_updated"),
            col("ce.ts_expires"),
            current_timestamp().alias("ts_load"),
        )


if __name__ == "__main__":
    job = CoreCreditEvaluationSparkJob()
    job.run()
