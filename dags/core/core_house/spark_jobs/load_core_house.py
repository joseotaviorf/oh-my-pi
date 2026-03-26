from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    broadcast,
    coalesce,
    col,
    current_timestamp,
    lit,
    row_number,
    year,
    month,
    dayofmonth,
)
from pyspark.sql.window import Window

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

JOB_NAME = "core_house"


class CoreHouseSparkJob(BaseCoreModelSparkJob):
    """Core House Spark job implementation."""

    def __init__(self):
        """Initialize the Core House Spark job."""
        super().__init__(JOB_NAME)

    def get_house_config(self):
        """Get house-specific configuration."""
        return {
            'ENTITY_TYPE': self.get_config("ENTITY_TYPE"),
            'HOUSE_TABLE': self.get_config("HOUSE_TABLE"),
            'HOUSE_LISTING_RELATION_TABLE': self.get_config("HOUSE_LISTING_RELATION_TABLE"),
            'USER_TABLE': self.get_config("USER_TABLE"),
        }

    def _load_house_data(self, spark, config, args):
        """Load and filter house data, including houses with updates in HLR."""
        house_df = spark.read.table(config['HOUSE_TABLE'])

        if (args.load_start_date is not None and args.load_start_date != "" and
            args.load_end_date is not None and args.load_end_date != ""):
            start_date = lit(args.load_start_date).cast("date")
            end_date = lit(args.load_end_date).cast("date")

            # House IDs that were updated in the House table
            house_updated_ids = house_df.filter(
                (col("ts_database_transaction").cast("date") >= start_date) &
                (col("ts_database_transaction").cast("date") <= end_date)
            ).select(col("id").alias("id_house"))

            # House IDs that were updated in the HLR table
            hlr_updated_ids = spark.read.table(config['HOUSE_LISTING_RELATION_TABLE']).filter(
                (col("ts_database_transaction").cast("date") >= start_date) &
                (col("ts_database_transaction").cast("date") <= end_date)
            ).select("id_house").distinct()

            # Union of IDs
            all_house_ids = house_updated_ids.union(hlr_updated_ids).distinct()

            # Returns complete records
            return house_df.join(
                broadcast(all_house_ids),  # Spark sends a complete copy to all executors
                house_df.id == all_house_ids.id_house,
                "left_semi"
            )

        return house_df

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core house model from EBDB data."""

        # Load configuration
        config = self.get_house_config()

        # Load source data
        house_df = self._load_house_data(spark, config, args)
        house_listing_relation_df = spark.read.table(config['HOUSE_LISTING_RELATION_TABLE'])
        user_df = spark.read.table(config['USER_TABLE'])

        # Filter houses - exclude legacy records (created before 2016 with no updates)
        filtered_houses_df = self._get_filtered_houses(house_df)

        # Get latest house listing relation for property owners
        latest_hlr_df = self._get_latest_house_listing_relation(house_listing_relation_df)

        # Build the core model
        result_df = self._build_core_house(
            filtered_houses_df,
            latest_hlr_df,
            user_df
        )

        # Generate surrogate key
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            result_df,
            config['ENTITY_TYPE'],
            id_column="id_house"
        )
        result_df = result_df.withColumnRenamed("surrogate_key", "sk_core_house")

        # Add ts_load column
        result_df = result_df.withColumn("ts_load", current_timestamp())

        # Add partitioning columns based on ts_updated
        result_df = result_df.withColumn("year", year(col("ts_updated"))) \
                            .withColumn("month", month(col("ts_updated"))) \
                            .withColumn("day", dayofmonth(col("ts_updated")))

        self.logger.info("m=create_core_model, msg=Core house model created")

        return result_df

    def _get_filtered_houses(self, house_df: DataFrame) -> DataFrame:
        """Filter houses excluding legacy records created before 2016 with no updates."""
        return house_df.filter(
            ~((year(col("dt_creation")) <= 2015) & col("ts_updated").isNull())
        ).select(
            col("id"),
            col("id_user"),
            col("id_external"),
            col("id_user_registrant"),
            col("id_region"),
            col("address"),
            col("number"),
            col("neighborhood"),
            col("complement"),
            col("zipcode"),
            col("city"),
            col("total_area"),
            col("lat"),
            col("lng"),
            col("type"),
            col("bathrooms"),
            col("bedrooms"),
            col("suites"),
            col("floor"),
            col("dt_creation"),
            col("ts_updated")
        )

    def _get_latest_house_listing_relation(self, house_listing_relation_df: DataFrame) -> DataFrame:
        """Get the latest house listing relation for property owners (MAIN_USER source)."""

        # Window for getting the latest record per house
        window_spec = Window.partitionBy("id_house").orderBy(col("ts_updated").desc())

        return house_listing_relation_df.filter(
            (col("related_as") == "PROPERTY_OWNER") &
            (col("source_type") == "MAIN_USER")
        ).withColumn(
            "row_num", row_number().over(window_spec)
        ).filter(
            col("row_num") == 1
        ).select(
            col("id_house"),
            col("id_related")
        )

    def _build_core_house(
        self,
        filtered_houses_df: DataFrame,
        latest_hlr_df: DataFrame,
        user_df: DataFrame
    ) -> DataFrame:
        """Build the core house model by joining filtered houses with owner information."""

        # Join houses with latest house listing relation
        result_df = filtered_houses_df.alias("h").join(
            latest_hlr_df.alias("hlr"),
            col("h.id") == col("hlr.id_house"),
            "left"
        )

        # Join with user table for owner from house_listing_relation
        result_df = result_df.join(
            user_df.alias("u1"),
            col("hlr.id_related") == col("u1.id"),
            "left"
        )

        # Join with user table for owner from house.id_user (fallback)
        result_df = result_df.join(
            user_df.alias("u2"),
            col("h.id_user") == col("u2.id"),
            "left"
        )

        # Select final columns
        return result_df.select(
            col("h.id").alias("id_house"),
            col("h.id_external"),
            col("h.id_region"),
            col("h.id_user_registrant"),
            coalesce(col("u1.id"), col("h.id_user")).alias("id_owner"),
            coalesce(col("u1.uuid_person"), col("u2.uuid_person")).alias("uuid_owner"),
            col("h.address"),
            col("h.number"),
            col("h.neighborhood"),
            col("h.complement"),
            col("h.zipcode"),
            col("h.city"),
            col("h.type"),
            col("h.total_area"),
            col("h.lat"),
            col("h.lng"),
            col("h.bathrooms").alias("total_bathrooms"),
            col("h.bedrooms").alias("total_bedrooms"),
            col("h.suites").alias("total_suites"),
            col("h.floor"),
            col("h.dt_creation").alias("ts_created"),
            col("h.ts_updated")
        )


if __name__ == "__main__":
    job = CoreHouseSparkJob()
    job.run()
