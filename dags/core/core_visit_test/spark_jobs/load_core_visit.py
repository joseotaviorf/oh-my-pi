# Databricks notebook source
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    when,
    lit,
    max,
    row_number,
    greatest,
    sha2,
    concat_ws,
)
from pyspark.sql.window import Window

from bietlejuice.base.spark.base_core_model_spark_job import BaseCoreModelSparkJob
from bietlejuice.base.core_models.helpers.surrogate_keys import SurrogateKeysHelper

JOB_NAME = "core_visit"

class CoreVisitSparkJob(BaseCoreModelSparkJob):
    """Core Visit Spark job implementation."""

    def __init__(self):
        """Initialize the Core Visit Spark job."""
        super().__init__(JOB_NAME)

    def get_visit_config(self):
        """Get visit-specific configuration."""
        return {
            'ENTITY_TYPE': self.get_config("ENTITY_TYPE"),
            'VISIT_TABLE': self.get_config("VISIT_TABLE"),
            'VISIT_STATUS_LOG_TABLE': self.get_config("VISIT_STATUS_LOG_TABLE"),
            'HOUSE_TABLE': self.get_config("HOUSE_TABLE"),
            'CONTRACT_TABLE': self.get_config("CONTRACT_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core visit model DataFrame."""
        # Get visit-specific configuration
        config = self.get_visit_config()

        # Read required tables
        vsl_df = spark.table(config['VISIT_STATUS_LOG_TABLE'])
        visit_df = spark.table(config['VISIT_TABLE'])
        house_df = spark.table(config['HOUSE_TABLE'])

        vsl_last_event_df = self._get_visit_last_event(vsl_df)
        all_events_df = self._get_visit_all_events(vsl_df)
        last_update_df = self._calculate_visit_last_update(visit_df, vsl_last_event_df, all_events_df)

        assembled_df = (
            visit_df.alias("v")
            .join(vsl_last_event_df.alias("vsl"), col("v.id") == col("vsl.id_visit"), "left")
            .join(all_events_df.alias("ae"), col("v.id") == col("ae.id_visit"), "left")
            .join(last_update_df.alias("le"), col("v.id") == col("le.id"))
            .join(house_df.alias("h"), col("v.id_house") == col("h.id"), "left")
            .select(
                col("v.id").alias("id_entity"), lit(config['ENTITY_TYPE']).alias("entity"), col("v.id_visitor"),
                col("h.id_user").alias("id_owner"), col("v.id_agent"), col("v.id_house"), col("v.business_context"),
                when(col("v.status").isNull(), col("v.computed_status")).otherwise(col("v.status")).alias("status"),
                when(col("v.status").isin("Canceled", "Done") | col("v.status").isNull() | col("v.computed_status").isin("CANCELED", "REQUEST_CANCELED", "UNSUCCESSFUL", "DONE"), False).otherwise(True).alias("is_active"),
                col("v.ts_created"), col("le.ts_updated_agg").alias("ts_updated"),
                col("vsl.id_schedule"), col("v.code"), col("v.slot"), col("v.computed_status"), col("vsl.event_type"), col("vsl.author_user_role"),
                col("vsl.on_behalf_of"), col("v.behavior"), col("v.booking_type"), col("v.structured"), col("v.business_model"),
                col("ae.cancellation_reason"), col("v.is_fixed_agent"), col("v.ts_visit"), col("v.dt_request"),
                col("ae.ts_visit_confirmed"), col("v.dt_confirmation_expiration"), col("ae.ts_visit_done"),
                col("ae.ts_visit_canceled"), col("ae.ts_visit_unsuccessful"), col("h.id_region"), col("h.address"),
                col("h.neighborhood"), col("h.number"), col("h.complement"), col("h.city"), col("h.zipcode"),
                col("h.is_for_rent"), col("h.is_for_sale")
            )
        )

        # Generate surrogate key using workflow utility
        result_df = SurrogateKeysHelper.generate_surrogate_key(assembled_df, config['ENTITY_TYPE'])

        # Apply schema validation - for now just return the dataframe
        # TODO: Implement schema validation if needed

        self.logger.info(f"m=create_core_model, msg=Core visit model created with {result_df.count()} records")

        return result_df

    @staticmethod
    def _get_visit_last_event(vsl_df: DataFrame) -> DataFrame:
        """(Unit Testable) Returns the last event for each visit."""
        vsl_window = Window.partitionBy("id_visit").orderBy(col("ts_created").desc())
        return vsl_df.withColumn("rn", row_number().over(vsl_window)).filter(col("rn") == 1)

    @staticmethod
    def _get_visit_all_events(vsl_df: DataFrame) -> DataFrame:
        """(Unit Testable) Aggregates all key event timestamps for each visit."""
        return vsl_df.groupBy("id_visit").agg(
            max(when(col("event_type").isin("VISIT_REQUEST_CANCELED", "VISIT_CANCELED"), col("reason"))).alias("cancellation_reason"),
            max(when(col("event_type") == "VISIT_CONFIRMED", col("ts_created"))).alias("ts_visit_confirmed"),
            max(when(col("event_type") == "VISIT_DONE", col("ts_created"))).alias("ts_visit_done"),
            max(when(col("event_type").isin("VISIT_REQUEST_CANCELED", "VISIT_CANCELED"), col("ts_created"))).alias("ts_visit_canceled"),
            max(when(col("event_type") == "VISIT_UNSUCCESSFUL", col("ts_created"))).alias("ts_visit_unsuccessful"),
        )

    @staticmethod
    def _calculate_visit_last_update(visit_df: DataFrame, vsl_last_event_df: DataFrame, all_events_df: DataFrame) -> DataFrame:
        """(Unit Testable) Calculates the true last update timestamp for a visit entity."""
        return (
            visit_df.alias("v")
            .join(vsl_last_event_df.alias("vsl"), col("v.id") == col("vsl.id_visit"), "left")
            .join(all_events_df.alias("ae"), col("v.id") == col("ae.id_visit"), "left")
            .select(
                col("v.id"),
                greatest(
                    col("v.ts_updated"), col("vsl.ts_created"), col("ae.ts_visit_confirmed"),
                    col("ae.ts_visit_done"), col("ae.ts_visit_canceled"), col("ae.ts_visit_unsuccessful")
                ).alias("ts_updated_agg")
            )
        )


if __name__ == "__main__":
    job = CoreVisitSparkJob()
    job.run()
