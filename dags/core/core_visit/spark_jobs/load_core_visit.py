from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col,
    coalesce,
    current_timestamp,
    lit,
    max as spark_max,
    row_number,
    when,
    year,
    month,
    dayofmonth,
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
            'HOUSE_LISTING_RELATION_TABLE': self.get_config("HOUSE_LISTING_RELATION_TABLE"),
            'EBDB_USER_TABLE': self.get_config("EBDB_USER_TABLE"),
        }

    def create_core_model(self, spark: SparkSession, args) -> DataFrame:
        """Create the core visit model from EBDB data."""

        # Load configuration
        config = self.get_visit_config()

        # Load source data
        visit_df = self._load_visit_data(spark, config, args)
        visit_status_log_df = self._load_visit_status_log_data(spark, config, args)
        house_df = self._load_house_data(spark, config)
        house_listing_relation_df = self._load_house_listing_relation_data(spark, config)
        user_df = self._load_user_data(spark, config)

        # Process visit status log - last event
        vsl_last_event_df = self._process_last_event(visit_status_log_df)
        
        # Process visit status log - all events
        all_events_df = self._process_all_events(visit_status_log_df)

        # Join all data
        result_df = self._join_all_data(
            visit_df, vsl_last_event_df, all_events_df, 
            house_df, house_listing_relation_df, user_df
        )

        # Generate surrogate key
        result_df = SurrogateKeysHelper.generate_surrogate_key(result_df, config['ENTITY_TYPE'])
        result_df = result_df.withColumnRenamed("sk_entity", "sk_core_visit")

        # Add partitioning columns
        result_df = result_df.withColumn("year", year(col("ts_updated"))) \
                            .withColumn("month", month(col("ts_updated"))) \
                            .withColumn("day", dayofmonth(col("ts_updated")))

        return result_df

    def _load_visit_data(self, spark, config, args):
        """Load and filter visit data."""
        visit_df = spark.read.table(config['VISIT_TABLE'])
        
        # Apply date filter if provided (for incremental loads)
        if (args.load_start_date is not None and args.load_start_date != "" and
            args.load_end_date is not None and args.load_end_date != ""):
            visit_df = visit_df.filter(
                (col("ts_updated").cast("date") >= lit(args.load_start_date).cast("date")) &
                (col("ts_updated").cast("date") <= lit(args.load_end_date).cast("date"))
            )
        
        return visit_df

    def _load_visit_status_log_data(self, spark, config, args):
        """Load visit status log data."""
        return spark.read.table(config['VISIT_STATUS_LOG_TABLE'])

    def _load_house_data(self, spark, config):
        """Load house data."""
        return spark.read.table(config['HOUSE_TABLE'])

    def _load_house_listing_relation_data(self, spark, config):
        """Load house listing relation data."""
        return spark.read.table(config['HOUSE_LISTING_RELATION_TABLE'])

    def _load_user_data(self, spark, config):
        """Load user data."""
        return spark.read.table(config['EBDB_USER_TABLE'])

    def _process_last_event(self, visit_status_log_df):
        """Process visit status log to get the last event per visit."""
        window_spec = Window.partitionBy("id_visit").orderBy(col("ts_created").desc())
        
        return visit_status_log_df.withColumn(
            "row_num", row_number().over(window_spec)
        ).filter(
            col("row_num") == 1
        ).select(
            col("id_visit"),
            col("event_type").alias("last_event_type")
        )

    def _process_all_events(self, visit_status_log_df):
        """Process all events to get aggregated event data per visit."""
        return visit_status_log_df.groupBy("id_visit").agg(
            spark_max(
                when(col("event_type").isin("VISIT_REQUEST_CANCELED", "VISIT_CANCELED"), col("reason"))
            ).alias("cancellation_reason"),
            
            spark_max(
                when(col("event_type") == "VISIT_REQUESTED", col("ts_created"))
            ).alias("ts_visit_requested"),
            
            spark_max(
                when(col("event_type") == "VISIT_CONFIRMED", col("ts_created"))
            ).alias("ts_visit_confirmed"),
            
            spark_max(
                when(col("event_type") == "VISIT_DONE", col("ts_created"))
            ).alias("ts_visit_done"),
            
            spark_max(
                when(col("event_type").isin("VISIT_REQUEST_CANCELED", "VISIT_CANCELED"), col("ts_created"))
            ).alias("ts_visit_canceled"),
            
            spark_max(
                when(col("event_type") == "VISIT_UNSUCCESSFUL", col("ts_created"))
            ).alias("ts_visit_unsuccessful")
        )

    def _join_all_data(self, visit_df, vsl_last_event_df, all_events_df, 
                       house_df, house_listing_relation_df, user_df):
        """Join all data sources to create the final result."""
        
        # Start with visit data
        result_df = visit_df
        
        # Join with last event
        result_df = result_df.alias("v").join(
            vsl_last_event_df.alias("vsl"),
            col("v.id") == col("vsl.id_visit"),
            "left"
        )
        
        # Join with all events
        result_df = result_df.join(
            all_events_df.alias("ae"),
            col("v.id") == col("ae.id_visit"),
            "left"
        )
        
        # Join with house
        result_df = result_df.join(
            house_df.alias("h"),
            col("v.id_house") == col("h.id"),
            "left"
        )
        
        # Join with house listing relation
        result_df = result_df.join(
            house_listing_relation_df.alias("hl"),
            (col("v.id_house") == col("hl.id")) & 
            (col("hl.related_as") == "PROPERTY_OWNER"),
            "left"
        )
        
        # Join with user (with complex OR condition)
        # id_related can be either a numeric ID (as string) or a UUID string
        result_df = result_df.join(
            user_df.alias("u"),
            (col("u.id").cast("string") == col("hl.id_related")) |
            (col("u.uuid_person") == col("hl.id_related")),
            "left"
        )
        
        # Select final columns
        return result_df.select(
            col("v.id").alias("id_visit"),
            col("v.id_house"),
            col("v.id_visitor"),
            coalesce(col("u.id"), col("h.id_user")).alias("id_owner"),
            col("v.id_agent"),
            col("v.code"),
            col("v.status"),
            col("v.computed_status"),
            col("v.type"),
            col("v.business_context"),
            col("vsl.last_event_type"),
            col("ae.cancellation_reason"),
            col("v.is_fixed_agent"),
            col("v.dt_visit"),
            col("v.ts_visit"),
            col("ae.ts_visit_requested"),
            col("ae.ts_visit_confirmed"),
            col("ae.ts_visit_done"),
            col("ae.ts_visit_canceled"),
            col("ae.ts_visit_unsuccessful"),
            col("v.ts_created"),
            col("v.ts_updated"),
            current_timestamp().alias("ts_load")
        )


