from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import (
    coalesce,
    col,
    current_timestamp,
    dayofmonth,
    first,
    lit,
    month,
    when,
    year,
)
from pyspark.sql.functions import (
    sum as F_sum,
)

from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper
from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob

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
            "REGION_BUSINESS_CONTEXTS_TABLE": self.get_config(
                "REGION_BUSINESS_CONTEXTS_TABLE"
            ),
            "REGION_CONFIG_TABLE": self.get_config("REGION_CONFIG_TABLE"),
            "STATE_TABLE": self.get_config("STATE_TABLE"),
            "COUNTRY_TABLE": self.get_config("COUNTRY_TABLE"),
        }

    @staticmethod
    def _apply_region_incremental_window(region_df: DataFrame, args) -> DataFrame:
        """Restrict rows to load window using Main business time (matches datalake_ebdb_clean.region)."""
        if (
            args.load_start_date is None
            or args.load_start_date == ""
            or args.load_end_date is None
            or args.load_end_date == ""
        ):
            return region_df

        ts_for_window = coalesce(col("ts_updated"), col("ts_created"))
        return region_df.filter(
            (ts_for_window.cast("date") >= args.load_start_date)
            & (ts_for_window.cast("date") <= args.load_end_date)
        )

    def _load_region_data(self, spark: SparkSession, config, args) -> DataFrame:
        """Load region table and apply incremental window (for tests and helpers)."""
        region_df = spark.table(config["REGION_TABLE"])
        return self._apply_region_incremental_window(region_df, args)

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core region model DataFrame."""
        config = self.get_region_config()

        # Full region dimension for parent joins; incremental filter applies to fact rows (r) only
        region_full_df = spark.table(config["REGION_TABLE"])
        region_r_df = self._apply_region_incremental_window(region_full_df, args)
        region_business_contexts_df = spark.table(
            config["REGION_BUSINESS_CONTEXTS_TABLE"]
        )
        region_config_df = spark.table(config["REGION_CONFIG_TABLE"])
        state_df = spark.table(config["STATE_TABLE"])
        country_df = spark.table(config["COUNTRY_TABLE"])

        region_config_by_region = region_config_df.groupBy("id_region").agg(
            first("phone_ddd", ignorenulls=True).alias("phone_ddd")
        )

        # CTE business_context:
        business_context_df = region_business_contexts_df.groupBy("id_region").agg(
            F_sum(when(col("business_context") == "RENT", 1).otherwise(0)).alias(
                "has_rent_operation_cnt"
            ),
            F_sum(when(col("business_context") == "SALE", 1).otherwise(0)).alias(
                "has_sale_operation_cnt"
            ),
        )

        # Region hierarchy: r respects incremental window; mr/sr use full table so parents resolve
        r = region_r_df.alias("r")
        mr = region_full_df.alias("mr")
        sr = region_full_df.alias("sr")

        joined_df = r.join(mr, col("mr.id") == col("r.id_parent_region"), "left").join(
            sr, col("sr.id") == col("mr.id_parent_region"), "left"
        )

        # State / country joins
        s = state_df.alias("s")
        c = country_df.alias("c")

        joined_df = joined_df.join(
            s,
            col("s.id")
            == coalesce(col("r.id_state"), col("mr.id_state"), col("sr.id_state")),
            "left",
        ).join(c, col("c.id") == col("s.id_country"), "left")

        # Cidade id along parent chain (same key as id_state propagation); region_config is keyed by Cidade only
        id_city_region = coalesce(col("sr.id"), col("mr.id"), col("r.id"))

        # Business context join
        bc = business_context_df.alias("bc")

        joined_df = joined_df.join(bc, col("bc.id_region") == col("r.id"), "left")

        rcfg = region_config_by_region.alias("rcfg")
        joined_df = joined_df.join(
            rcfg, col("rcfg.id_region") == id_city_region, "left"
        )

        # Apply WHERE c.code IS NOT NULL
        filtered_df = joined_df.filter(col("c.code").isNotNull())

        city_region_name = coalesce(col("sr.name"), col("mr.name"), col("r.name"))
        # Align with enrich_region: English display names by EBDB country id (not raw c.name).
        country_name = (
            when(col("s.id_country") == 1, lit("Brazil"))
            .when(col("s.id_country") == 2, lit("Mexico"))
            .otherwise(col("c.name"))
        )

        greater_region = (
            when(
                city_region_name.isin("Rio de Janeiro", "Campinas"),
                city_region_name,
            )
            .when(
                city_region_name.isin(
                    "São Paulo",
                    "São Bernardo do Campo",
                    "São Caetano do Sul",
                    "Santo André",
                    "Guarulhos",
                    "Osasco",
                    "Barueri",
                ),
                lit("Grande São Paulo"),
            )
            .otherwise(lit(None).cast("string"))
        )

        # Final projection & renaming to core conventions
        core_region_df = filtered_df.select(
            col("r.id").alias("id_region"),
            col("r.id_parent_region"),
            id_city_region.alias("id_city_region"),
            col("mr.id").alias("id_macro_region"),
            col("r.name").alias("region_name"),
            city_region_name.alias("city_region_name"),
            col("r.level"),
            coalesce(col("r.id_state"), col("mr.id_state"), col("sr.id_state")).alias(
                "id_state"
            ),
            col("s.name").alias("state_name"),
            col("s.abbreviation").alias("state_abbreviation"),
            col("s.id_country"),
            col("c.code").alias("country_code"),
            country_name.alias("country_name"),
            col("c.default_timezone").alias("country_default_timezone"),
            col("rcfg.phone_ddd").cast("string").alias("region_phone_ddd"),
            greater_region.alias("greater_region"),
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
            core_region_df.withColumn("ts_load", current_timestamp())
            .withColumn("year", year(col("ts_region_updated")))
            .withColumn("month", month(col("ts_region_updated")))
            .withColumn("day", dayofmonth(col("ts_region_updated")))
        )

        self.logger.info("m=create_core_model, msg=Core region model created")

        return core_region_df


if __name__ == "__main__":
    job = CoreRegionSparkJob()
    job.run()
