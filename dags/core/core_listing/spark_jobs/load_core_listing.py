from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    coalesce,
    col,
    concat,
    current_timestamp,
    lit,
    lpad,
    max as spark_max,
    row_number,
    sha2,
    when,
    year,
    month,
    dayofmonth,
)
from pyspark.sql.window import Window

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

JOB_NAME = "core_listing"


class CoreListingSparkJob(BaseCoreModelSparkJob):
    """Core Listing Spark job implementation."""

    def __init__(self):
        """Initialize the Core Listing Spark job."""
        super().__init__(JOB_NAME)

    def get_listing_config(self):
        """Get listing-specific configuration."""
        return {
            'ENTITY_TYPE': self.get_config("ENTITY_TYPE"),
            'LISTING_BUSINESS_CONTEXT_TABLE': self.get_config("LISTING_BUSINESS_CONTEXT_TABLE"),
            'HOUSE_TABLE': self.get_config("HOUSE_TABLE"),
            'AUX_LBC_STATUS_VERSION_ORDER_TABLE': self.get_config("AUX_LBC_STATUS_VERSION_ORDER_TABLE"),
            'AUX_HOUSE_LISTING_CATEGORY_TABLE': self.get_config("AUX_HOUSE_LISTING_CATEGORY_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core listing model from EBDB data."""

        # Load configuration
        config = self.get_listing_config()

        # Load source data
        listing_business_context_df = spark.read.table(config['LISTING_BUSINESS_CONTEXT_TABLE'])
        house_df = spark.read.table(config['HOUSE_TABLE'])
        aux_lbc_status_version_order_df = spark.read.table(config['AUX_LBC_STATUS_VERSION_ORDER_TABLE'])
        aux_house_listing_category_df = spark.read.table(config['AUX_HOUSE_LISTING_CATEGORY_TABLE'])

        # Process RENT listings
        rent_df = self._process_rent_listings(
            listing_business_context_df,
            house_df,
            aux_lbc_status_version_order_df,
            aux_house_listing_category_df
        )

        # Process SALE listings
        sale_df = self._process_sale_listings(listing_business_context_df, house_df)

        # Union RENT and SALE listings by column name
        result_df = rent_df.unionByName(sale_df)

        # Generate surrogate key
        result_df = SurrogateKeysHelper.generate_surrogate_key(result_df, config['ENTITY_TYPE'], id_column="id_listing")
        result_df = result_df.withColumnRenamed("surrogate_key", "sk_core_listing")

        # Add ts_load column
        result_df = result_df.withColumn("ts_load", current_timestamp())

        # Add partitioning columns based on ts_updated
        result_df = result_df.withColumn("year", year(col("ts_updated"))) \
                            .withColumn("month", month(col("ts_updated"))) \
                            .withColumn("day", dayofmonth(col("ts_updated")))

        self.logger.info("m=create_core_model, msg=Core listing model created")

        return result_df

    def _process_rent_listings(
        self,
        listing_business_context_df: DataFrame,
        house_df: DataFrame,
        aux_lbc_status_version_order_df: DataFrame,
        aux_house_listing_category_df: DataFrame
    ) -> DataFrame:
        """Process RENT listings from listing_business_context and aux__lbc_status_version_order tables."""

        # Filter RENT listings in listing_business_context table and join with house
        lbc_rent_df = listing_business_context_df.filter(
            col("business_context") == "RENT"
        ).alias("lbc_base").join(
            house_df.select(
                col("id"),
                col("rent"),
                col("total_value"),
                col("condo"),
                col("iptu"),
                col("condo_type"),
                col("iptu_type")
            ).alias("h"),
            col("lbc_base.id_house") == col("h.id"),
            "left"
        ).select(
            col("lbc_base.id_house"),
            col("lbc_base.id"),
            col("h.rent"),
            col("h.total_value"),
            col("h.condo"),
            col("h.iptu"),
            col("h.condo_type"),
            col("h.iptu_type"),
            col("lbc_base.ownership"),
            col("lbc_base.ts_first_publication"),
            col("lbc_base.ts_last_publication"),
            col("lbc_base.ts_created"),
            col("lbc_base.business_context")
        )

        # Create id_house_listing expression
        id_house_listing_expr = concat(
            col("id_house").cast("string"),
            lpad(col("listing_version").cast("string"), 3, "0")
        ).cast("bigint")

        # Window for deduplication
        dedup_window = Window.partitionBy("id_house_listing").orderBy(
            col("ts_state_started").desc(),
            coalesce(col("ts_state_ended"), current_timestamp()).desc()
        )

        # Window for max_listing_version
        house_window = Window.partitionBy("id_house")

        # Process rent_base from aux__lbc_status_version_order table
        rent_base_df = aux_lbc_status_version_order_df.select(
            col("id_house"),
            col("listing_version"),
            id_house_listing_expr.alias("id_house_listing"),
            col("status"),
            col("status_reason"),
            col("is_extended_rental"),
            col("has_termination_canceled"),
            col("ts_state_started"),
            col("ts_state_ended")
        ).withColumn(
            "max_listing_version", spark_max("listing_version").over(house_window)
        ).withColumn(
            "row_num", row_number().over(dedup_window)
        ).filter(
            col("row_num") == 1
        ).drop("row_num", "ts_state_ended")

        # INNER JOIN rent_base with lbc_rent
        rent_joined_df = rent_base_df.alias("rb").join(
            lbc_rent_df.alias("lbc"),
            col("rb.id_house") == col("lbc.id_house"),
            "inner"
        )

        # INNER JOIN with aux__house_listing_category table
        rent_joined_df = rent_joined_df.join(
            aux_house_listing_category_df.alias("hlc"),
            (col("hlc.id_house") == col("rb.id_house")) &
            (col("hlc.id_house_listing") == col("rb.id_house_listing")),
            "inner"
        )

        # Select final RENT columns
        rent_df = rent_joined_df.select(
            col("rb.id_house"),
            col("lbc.id").alias("id_listing_business_context"),
            col("rb.id_house_listing"),
            sha2(
                concat(
                    col("rb.id_house_listing").cast("string"),
                    col("lbc.business_context")
                ),
                256
            ).alias("id_listing"),
            col("rb.listing_version").alias("version"),
            col("lbc.rent").alias("price"),
            col("lbc.total_value"),
            col("lbc.condo").alias("condo_value"),
            col("lbc.iptu").alias("iptu_value"),
            col("lbc.condo_type"),
            col("lbc.iptu_type"),
            col("rb.status"),
            col("rb.status_reason"),
            when(
                (col("rb.listing_version") == 0) & col("hlc.listing_category").isNull(),
                lit("NA")
            ).otherwise(col("hlc.listing_category")).alias("category"),
            col("lbc.ownership"),
            col("lbc.business_context"),
            col("rb.is_extended_rental"),
            col("rb.has_termination_canceled"),
            (col("rb.max_listing_version") == col("rb.listing_version")).alias("is_last_listing_version"),
            col("lbc.ts_first_publication"),
            col("lbc.ts_last_publication"),
            col("lbc.ts_created"),
            col("rb.ts_state_started").alias("ts_updated")
        )

        return rent_df

    def _process_sale_listings(
        self,
        listing_business_context_df: DataFrame,
        house_df: DataFrame
    ) -> DataFrame:
        """Process SALE listings from listing_business_context table."""

        # Expression for id_house_listing
        id_house_listing_expr = concat(col("lbc.id_house").cast("string"), lit("000")).cast("bigint")

        # Filter SALE listings and join with house table
        sale_filtered_df = listing_business_context_df.filter(
            (col("business_context") == "SALE") &
            ~((year(col("ts_created")) <= 2022) & col("ts_updated").isNull())
        ).alias("lbc")

        sale_joined_df = sale_filtered_df.join(
            house_df.select(
                col("id"),
                col("sale_price"),
                col("total_value"),
                col("condo"),
                col("iptu"),
                col("condo_type"),
                col("iptu_type")
            ).alias("h"),
            col("lbc.id_house") == col("h.id"),
            "left"
        )

        sale_df = sale_joined_df.select(
            col("lbc.id_house"),
            col("lbc.id").alias("id_listing_business_context"),
            id_house_listing_expr.alias("id_house_listing"),
            sha2(
                concat(
                    id_house_listing_expr.cast("string"),
                    col("lbc.business_context")
                ),
                256
            ).alias("id_listing"),
            lit(0).alias("version"),
            col("h.sale_price").alias("price"),
            col("h.total_value"),
            col("h.condo").alias("condo_value"),
            col("h.iptu").alias("iptu_value"),
            col("h.condo_type"),
            col("h.iptu_type"),
            col("lbc.status"),
            col("lbc.status_reason"),
            lit("NA").alias("category"),
            col("lbc.ownership"),
            col("lbc.business_context"),
            lit(False).alias("is_extended_rental"),
            lit(False).alias("has_termination_canceled"),
            lit(True).alias("is_last_listing_version"),
            col("lbc.ts_first_publication"),
            col("lbc.ts_last_publication"),
            col("lbc.ts_created"),
            col("lbc.ts_updated")
        )

        return sale_df


if __name__ == "__main__":
    job = CoreListingSparkJob()
    job.run()
