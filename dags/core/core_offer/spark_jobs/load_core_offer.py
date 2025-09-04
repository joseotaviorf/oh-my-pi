from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    lit,
    year,
    month,
    dayofmonth,
    current_timestamp,
)

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

JOB_NAME = "core_offer"
class CoreOfferSparkJob(BaseCoreModelSparkJob):
    """Core Offer Spark job implementation."""

    def __init__(self):
        """Initialize the Core Offer Spark job."""
        super().__init__(JOB_NAME)

    def get_offer_config(self):
        """Get offer-specific configuration."""
        return {
            'ENTITY_TYPE': self.get_config("ENTITY_TYPE"),
            'RENTAL_TRANSACT_OFFER_TABLE': self.get_config("RENTAL_TRANSACT_OFFER_TABLE"),
            'EBDB_USER_TABLE': self.get_config("EBDB_USER_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core offer model DataFrame."""
        # Get offer-specific configuration
        config = self.get_offer_config()

        # Log execution mode based on date parameters
        if (args.load_start_date is not None and args.load_start_date != "" and
            args.load_end_date is not None and args.load_end_date != ""):
            self.logger.info(f"m=create_core_model, mode=INCREMENTAL, load_start_date={args.load_start_date}, load_end_date={args.load_end_date}")
        else:
            self.logger.info("m=create_core_model, mode=FULL, msg=Running full load without date filtering")

        # Read required tables
        rental_transact_offer_df = spark.table(config['RENTAL_TRANSACT_OFFER_TABLE'])
        ebdb_user_df = spark.table(config['EBDB_USER_TABLE'])

        # Apply date filter if provided (to rental_transact table)
        if (args.load_start_date is not None and args.load_start_date != "" and
            args.load_end_date is not None and args.load_end_date != ""):
            rental_transact_offer_df = rental_transact_offer_df.filter(
                (col("ts_database_transaction").cast("date") >= lit(args.load_start_date).cast("date")) &
                (col("ts_database_transaction").cast("date") <= lit(args.load_end_date).cast("date"))
            )

        # Filter out deleted records (op_cdc <> 'd')
        rental_transact_offer_df = rental_transact_offer_df.filter(col("op_cdc") != lit("d"))

        # Performs left joins to get the internal identifiers from EBDB
        assembled_df = (
            rental_transact_offer_df.alias("o_rental_transact")
            .join(
                ebdb_user_df.alias("tenant"),
                col("tenant.uuid_person") == col("o_rental_transact.id_tenant_external"),
                "left"
            )
            .join(
                ebdb_user_df.alias("owner"),
                col("owner.uuid_person") == col("o_rental_transact.id_owner_external"),
                "left"
            )
            .select(
                col("o_rental_transact.id").alias("id_offer"),
                col("tenant.id").alias("id_tenant"),
                col("o_rental_transact.id_tenant_external"),
                col("owner.id").alias("id_owner"),
                col("o_rental_transact.id_owner_external"),
                col("o_rental_transact.id_resident_info"),
                col("o_rental_transact.id_house_external").alias("id_house"),
                col("o_rental_transact.status"),
                col("o_rental_transact.type"),
                col("o_rental_transact.turn"),
                col("o_rental_transact.iteration"),
                col("o_rental_transact.rejection_reason"),
                col("o_rental_transact.original_rent_value"),
                col("o_rental_transact.ts_created"),
                col("o_rental_transact.ts_updated"),
                col("o_rental_transact.ts_expiration"),
                current_timestamp().alias("ts_load")
            )
        )

        # Generate surrogate key using workflow utility
        result_df = SurrogateKeysHelper.generate_surrogate_key(assembled_df, config['ENTITY_TYPE'], "id_offer")
        result_df = result_df.withColumnRenamed("surrogate_key", "sk_core_offer")

        # Add partitioning columns
        result_df = result_df.withColumn("year", year(col("ts_created")))
        result_df = result_df.withColumn("month", month(col("ts_created")))
        result_df = result_df.withColumn("day", dayofmonth(col("ts_created")))

        self.logger.info(f"m=create_core_model, msg=Core offer model created with {result_df.count()} records")

        return result_df


if __name__ == "__main__":
    job = CoreOfferSparkJob()
    job.run()
