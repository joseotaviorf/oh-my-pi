from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    coalesce,
    when,
    sum as F_sum,
    current_timestamp,
    year,
    month,
    dayofmonth,
)
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

JOB_NAME = "core_region"


class CoreRegionSparkJob(BaseCoreModelSparkJob):
    """Core Region Spark job implementation."""

    def __init__(self):
        super().__init__(JOB_NAME)

    def get_region_config(self):
        """Get region-specific configuration (table names, entity type, etc.)."""
        return {
            "ENTITY_TYPE": self.get_config("ENTITY_TYPE"),
            "REGION_TABLE": self.get_config("REGION_TABLE"),
            "REGION_BUSINESS_CONTEXTS_TABLE": self.get_config("REGION_BUSINESS_CONTEXTS_TABLE"),
            "STATE_TABLE": self.get_config("STATE_TABLE"),
            "COUNTRY_TABLE": self.get_config("COUNTRY_TABLE"),
            "BUSINESS_UNIT_REGION_TABLE": self.get_config("BUSINESS_UNIT_REGION_TABLE"),
            "BUSINESS_UNIT_TABLE": self.get_config("BUSINESS_UNIT_TABLE"),
        }

    def _load_region_data(self, spark: SparkSession, config, args) -> DataFrame:
        """Load region table, optionally applying incremental date filter."""
        region_df = spark.table(config["REGION_TABLE"])

        if (
            args.load_start_date is not None
            and args.load_start_date != ""
            and args.load_end_date is not None
            and args.load_end_date != ""
        ):
            # Incremental window on ts_updated
            region_df = region_df.filter(
                (col("ts_updated").cast("date") >= args.load_start_date)
                & (col("ts_updated").cast("date") <= args.load_end_date)
            )

        return region_df

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core region model DataFrame."""
        config = self.get_region_config()

        # Source tables
        region_df = self._load_region_data(spark, config, args)
        region_business_contexts_df = spark.table(config["REGION_BUSINESS_CONTEXTS_TABLE"])
        state_df = spark.table(config["STATE_TABLE"])
        country_df = spark.table(config["COUNTRY_TABLE"])
        business_unit_region_df = spark.table(config["BUSINESS_UNIT_REGION_TABLE"])
        business_unit_df = spark.table(config["BUSINESS_UNIT_TABLE"])

        # CTE business_context:
        business_context_df = (
            region_business_contexts_df.groupBy("id_region")
            .agg(
                F_sum(
                    when(col("business_context") == "RENT", 1).otherwise(0)
                ).alias("has_rent_operation_cnt"),
                F_sum(
                    when(col("business_context") == "SALE", 1).otherwise(0)
                ).alias("has_sale_operation_cnt"),
            )
        )

        # Region hierarchy joins (r, mr, sr)
        r = region_df.alias("r")
        mr = region_df.alias("mr")
        sr = region_df.alias("sr")

        joined_df = (
            r
            .join(mr, col("mr.id") == col("r.id_parent_region"), "left")
            .join(sr, col("sr.id") == col("mr.id_parent_region"), "left")
        )

        # State / country joins
        s = state_df.alias("s")
        c = country_df.alias("c")

        joined_df = (
            joined_df
            .join(
                s,
                col("s.id") == coalesce(col("r.id_state"), col("mr.id_state"), col("sr.id_state")),
                "left",
            )
            .join(c, col("c.id") == col("s.id_country"), "left")
        )

        # Business context and hub joins
        bc = business_context_df.alias("bc")
        br = business_unit_region_df.alias("br")
        bu = business_unit_df.alias("bu")

        joined_df = (
            joined_df
            .join(bc, col("bc.id_region") == col("r.id"), "left")
            .join(br, col("br.id_region") == col("r.id"), "left")
            .join(bu, col("bu.id") == col("br.id_business_unit"), "left")
        )

        # Apply WHERE c.code IS NOT NULL
        filtered_df = joined_df.filter(col("c.code").isNotNull())

        # Final projection & renaming to core conventions
        core_region_df = filtered_df.select(
            col("r.id").alias("id_region"),
            col("r.id_parent_region"),
            col("r.name").alias("region_name"),
            col("r.level"),
            coalesce(col("r.id_state"), col("mr.id_state"), col("sr.id_state")).alias("id_state"),
            col("s.name").alias("state_name"),
            col("s.abbreviation").alias("state_abbreviation"),
            col("s.id_country"),
            col("c.code").alias("country_code"),
            col("c.name").alias("country_name"),
            col("c.default_timezone").alias("country_default_timezone"),
            col("bu.hub_name"),
            when(col("bc.has_rent_operation_cnt") == 1, True)
            .otherwise(False)
            .alias("has_rent_operation"),
            when(col("bc.has_sale_operation_cnt") == 1, True)
            .otherwise(False)
            .alias("has_sale_operation"),
            col("r.ts_created").alias("ts_region_created"),
            col("r.ts_updated").alias("ts_region_updated"),
        )

        # Surrogate key
        core_region_df = SurrogateKeysHelper.generate_surrogate_key(
            core_region_df,
            config["ENTITY_TYPE"],
            id_column="id_region",
        ).withColumnRenamed("surrogate_key", "sk_core_region")

        # ts_load + partitions (based on ts_region_updated)
        core_region_df = (
            core_region_df
            .withColumn("ts_load", current_timestamp())
            .withColumn("year", year(col("ts_region_updated")))
            .withColumn("month", month(col("ts_region_updated")))
            .withColumn("day", dayofmonth(col("ts_region_updated")))
        )

        self.logger.info("m=create_core_model, msg=Core region model created")

        return core_region_df


if __name__ == "__main__":
    job = CoreRegionSparkJob()
    job.run()
