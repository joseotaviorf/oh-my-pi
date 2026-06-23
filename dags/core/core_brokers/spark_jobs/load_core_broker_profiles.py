from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, current_timestamp, lit, when

from bietlejuice.base.core_models.core_brokers_base import CoreBrokersBaseSparkJob


class CoreBrokerProfilesSparkJob(CoreBrokersBaseSparkJob):
    """Build ``brokers_profile`` from clean-layer member_profile, profile, and product.

    One row per member_profile for 3P products (id_product 27 sale, 30 rent).
    """

    def get_brokers_profile_config(self):
        return {
            "MEMBER_PROFILE_TABLE": self.get_config("MEMBER_PROFILE_TABLE"),
            "PROFILE_TABLE": self.get_config("PROFILE_TABLE"),
            "PRODUCT_TABLE": self.get_config("PRODUCT_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        config = self.get_brokers_profile_config()

        member_profile_df = self._load_data(
            spark,
            config["MEMBER_PROFILE_TABLE"],
            args,
        )
        profile_df = spark.read.table(config["PROFILE_TABLE"])
        product_df = spark.read.table(config["PRODUCT_TABLE"])

        filtered_mp = member_profile_df.filter(col("id_product").isin(27, 30)).alias(
            "mp"
        )
        joined = filtered_mp.join(
            profile_df.alias("pf"),
            col("mp.id_profile") == col("pf.id"),
            "left",
        ).join(
            product_df.alias("pd"),
            col("mp.id_product") == col("pd.id"),
            "left",
        )

        return joined.select(
            col("mp.id").cast("string").alias("sk_broker_profile"),
            col("mp.id_company").cast("string").alias("sk_broker"),
            col("mp.uuid_person"),
            col("pd.name").alias("product_name"),
            when(col("mp.id_product") == 27, lit("SALE"))
            .when(col("mp.id_product") == 30, lit("RENT"))
            .alias("business_context"),
            col("pf.profile_name").alias("profile"),
            col("mp.status").alias("profile_status"),
            (col("mp.status") == lit("ACTIVE")).alias("is_active_profile"),
            (col("mp.id_profile") == lit(17)).alias("is_agent"),
            (col("mp.id_profile") == lit(13)).alias("is_broker_admin"),
            lit(True).alias("has_3p_access_control"),
            col("mp.ts_created").alias("ts_profile_created"),
            col("mp.ts_updated").alias("ts_profile_updated"),
            current_timestamp().alias("ts_load"),
            col("mp.year"),
            col("mp.month"),
            col("mp.day"),
        )

    def run_pipeline(self, dataframe: DataFrame, args, spark: SparkSession) -> None:
        self._run_pipeline_with_config(
            dataframe,
            args,
            spark,
            merge_on_key="merge_on_brokers_profile",
            update_condition_key="when_matched_update_condition_brokers_profile",
        )


if __name__ == "__main__":
    job = CoreBrokerProfilesSparkJob()
    job.run()
