from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    coalesce,
    lit,
    get_json_object,
    concat_ws,
    sha2,
    year,
    month,
    dayofmonth,
    current_timestamp,
)

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

JOB_NAME = "core_contract"


class CoreContractSparkJob(BaseCoreModelSparkJob):
    """Core Contract Spark job implementation."""

    def __init__(self):
        """Initialize the Core Contract Spark job."""
        super().__init__(JOB_NAME)

    def get_contract_config(self):
        """Get contract-specific configuration."""
        return {
            "ENTITY_TYPE": self.get_config("ENTITY_TYPE"),
            "CONTRACT_TABLE": self.get_config("CONTRACT_TABLE"),
            "HOUSE_TABLE": self.get_config("HOUSE_TABLE"),
            "HOUSE_LISTING_RELATION_TABLE": self.get_config(
                "HOUSE_LISTING_RELATION_TABLE"
            ),
            "EBDB_USER_TABLE": self.get_config("EBDB_USER_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core contract model from EBDB data."""

        config = self.get_contract_config()
        self.logger.info(
            f"m=create_core_model, msg=Loading data for date range: {args.load_start_date} to {args.load_end_date}"
        )

        # Load source data
        contract_df = self._load_contract_data(spark, config, args)
        house_df = self._load_house_data(spark, config)
        house_listing_relation_df = self._load_house_listing_relation_data(
            spark, config
        )
        user_df = self._load_user_data(spark, config)

        # Join all data
        result_df = self._join_all_data(
            contract_df, house_df, house_listing_relation_df, user_df
        )

        # Generate surrogate key
        result_df = SurrogateKeysHelper.generate_surrogate_key(
            result_df, config["ENTITY_TYPE"], id_column="id_contract"
        )
        result_df = result_df.withColumnRenamed("surrogate_key", "sk_core_contract")

        # Add partitioning columns
        result_df = (
            result_df.withColumn("year", year(col("ts_updated")))
            .withColumn("month", month(col("ts_updated")))
            .withColumn("day", dayofmonth(col("ts_updated")))
        )

        return result_df

    def _load_contract_data(self, spark, config, args):
        """Load and filter contract data."""
        contract_df = spark.table(config["CONTRACT_TABLE"])

        # Apply date filter for incremental loads
        contract_df = contract_df.filter(
            (
                col("ts_database_transaction").cast("date")
                >= lit(args.load_start_date).cast("date")
            )
            & (
                col("ts_database_transaction").cast("date")
                <= lit(args.load_end_date).cast("date")
            )
        )

        return contract_df

    def _load_house_data(self, spark, config):
        """Load house data."""
        self.logger.debug(f"Loading house data from {config['HOUSE_TABLE']}")

        return spark.table(config["HOUSE_TABLE"])

    def _load_house_listing_relation_data(self, spark, config):
        """Load house listing relation data."""
        self.logger.debug(
            f"Loading house listing relation data from {config['HOUSE_LISTING_RELATION_TABLE']}"
        )

        return spark.table(config["HOUSE_LISTING_RELATION_TABLE"])

    def _load_user_data(self, spark, config):
        """Load user data."""
        self.logger.debug(f"Loading user data from {config['EBDB_USER_TABLE']}")

        return spark.table(config["EBDB_USER_TABLE"])

    def _join_all_data(self, contract_df, house_df, house_listing_relation_df, user_df):
        """Join all data sources to create the final result."""

        result_df = contract_df.alias("ct")

        result_df = result_df.join(
            house_df.alias("h"), col("ct.id_house") == col("h.id"), "left"
        )

        result_df = result_df.join(
            house_listing_relation_df.alias("hl"),
            (col("ct.id_house") == col("hl.id"))
            & (col("hl.related_as") == "PROPERTY_OWNER"),
            "left",
        )

        result_df = result_df.join(
            user_df.alias("u"),
            (col("u.id").cast("string") == col("hl.id_related"))
            | (col("u.uuid_person") == col("hl.id_related")),
            "left",
        )

        return result_df.select(
            col("ct.id").alias("id_contract"),
            col("ct.id_house"),
            col("ct.id_user").alias("id_tenant"),
            coalesce(col("u.id"), col("h.id_user")).alias("id_owner"),
            col("ct.id_proposal"),
            col("ct.status"),
            coalesce(
                get_json_object(col("ct.contract_rent_model"), "$.rentalAdministrator"),
                lit("QUINTOANDAR"),
            ).alias("rental_administrator"),
            col("ct.paying_condo"),
            col("ct.responsible_for_condo"),
            col("ct.paying_iptu"),
            col("ct.responsible_for_iptu"),
            col("ct.signature_type"),
            col("ct.status_closing"),
            coalesce(col("ct.is_relisting_enabled"), lit(False)).alias(
                "is_relisting_enabled"
            ),
            # Keep original data types as per schema specification
            col("ct.rent"),
            col("ct.iptu"),
            col("ct.rental_guarantee_installment"),
            col("ct.rental_guarantee_value"),
            col("ct.home_insurance_installment"),
            col("ct.home_insurance_value"),
            col("ct.fist_rent_comission_fee").alias("first_rent_comission_fee"),
            col("ct.tenant_service_fee"),
            col("ct.agent_brokerage_share"),
            col("ct.dt_started"),
            col("ct.dt_entered"),
            col("ct.dt_termination"),
            # Keep original data types as per schema specification
            col("ct.ts_contract_expected_end").cast("date"),
            col("ct.ts_signed"),
            col("ct.ts_expected_termination").cast("date"),
            col("ct.ts_minuta_approved"),
            col("ct.ts_created"),
            col("ct.ts_updated"),
            current_timestamp().alias("ts_load"),
            # Add partitioning columns
            year(col("ct.ts_created")).alias("year"),
            month(col("ct.ts_created")).alias("month"),
            dayofmonth(col("ct.ts_created")).alias("day"),
        )


if __name__ == "__main__":
    job = CoreContractSparkJob()
    job.run()
