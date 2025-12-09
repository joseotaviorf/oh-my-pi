import time

from pyspark.sql import functions as F

import logging
from typing import Any, Dict, List

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.streaming import StreamingQueryListener
from pyspark.sql.streaming.listener import (
    QueryIdleEvent,
    QueryProgressEvent,
    QueryStartedEvent,
    QueryTerminatedEvent,
)


logger = logging.getLogger(__name__)


def cdf_to_kafka_format(
    cdf_dataframe: DataFrame, key_columns: List[str], source_table: str
) -> DataFrame:
    """Convert CDF DataFrame to Kafka format with headers, key, and value columns.

    Args:
        cdf_dataframe: DataFrame with CDF columns
        key_columns: List of column names to use as Kafka key
        source_table: Source table name

    Returns:
        DataFrame with 3 columns: headers, key, value
    """
    # CDF metadata columns that should go to headers
    cdf_metadata_columns = ["_change_type", "_commit_version", "_commit_timestamp"]

    all_columns = cdf_dataframe.columns

    cdf_columns = [col for col in all_columns if col in cdf_metadata_columns]
    data_columns = [col for col in all_columns if col not in cdf_columns]

    header_structs = []
    for col in cdf_columns:
        header_structs.append(
            F.struct(
                F.lit(col).alias("key"),
                F.col(col).cast("string").cast("binary").alias("value"),
            )
        )

    header_structs.append(
        F.struct(
            F.lit("_source_table").alias("key"),
            F.lit(source_table).cast("string").cast("binary").alias("value"),
        )
    )

    # Create headers column as array of structs
    headers_col = F.array(*header_structs).alias("headers")

    key_col = F.to_json(F.struct(*[F.col(col) for col in key_columns])).alias("key")

    value_col = F.to_json(F.struct(*[F.col(col) for col in data_columns])).alias(
        "value"
    )

    return cdf_dataframe.select(headers_col, key_col, value_col)


class CDFToKafkaStreamListener(StreamingQueryListener):
    """Listener for CDF to Kafka streaming query events."""

    def __init__(self):
        self.start_time = None

        self.total_rows_written = 0
        self.batches_processed = 0

    def onQueryStarted(self, event: QueryStartedEvent) -> None:
        self.start_time = time.time()
        logger.info("=== onQueryStarted called ===")
        logger.info(
            f"Streaming query started: id={event.id}, name={event.name}, runId={event.runId}"
        )

    def onQueryProgress(self, event: QueryProgressEvent) -> None:
        logger.info("=== onQueryProgress called ===")

        self.total_rows_written += event.progress.numInputRows

        logger.info(f"Batch ID: {event.progress.batchId}")
        logger.info(f"Rows in this batch: {event.progress.numInputRows}")
        logger.info(f"Total rows written: {self.total_rows_written}")
        logger.info(f"Batch duration: {event.progress.batchDuration}ms")
        logger.info(
            f"Processing rate: {event.progress.processedRowsPerSecond} rows/sec"
        )

    def onQueryIdle(self, event: QueryIdleEvent) -> None:
        logger.info("onQueryIdle called")
        logger.info(f"Query is idle (no new data to process) id={event.id}")

    def onQueryTerminated(self, event: QueryTerminatedEvent) -> None:
        logger.info("onQueryTerminated called")
        duration = time.time() - self.start_time if self.start_time else 0

        logger.info(f"Query terminated id={event.id} duration={duration:.2f}s")
        logger.info(f"Total batches processed: {self.batches_processed}")
        logger.info(f"Total rows written to Kafka: {self.total_rows_written}")

        if event.exception:
            logger.error(f"Query failed with exception: {event.exception}")
        else:
            logger.info("Query terminated successfully with no exceptions")


def write_to_kafka(
    df: DataFrame, kafka_options: Dict[str, Any], checkpoint_location: str
) -> None:
    """Write the transformed data to Kafka topic."""
    query = (
        df.writeStream.format("kafka")
        .options(**kafka_options)
        .option("checkpointLocation", checkpoint_location)
        .trigger(availableNow=True)
        .outputMode("append")
        .start()
    )

    logger.info(f"Started streaming to Kafka topic '{kafka_options['topic']}' ")

    logger.info(
        "Forcing the KafkaStreamListener to be called... (by sleeping for 30 seconds)"
    )
    time.sleep(30)

    query.awaitTermination()


def read_cdf_stream(spark: SparkSession, table_name: str) -> DataFrame:
    """Read from Delta Change Data Feed as a streaming DataFrame."""
    return (
        spark.readStream.format("delta")
        .option("readChangeFeed", "true")
        .table(table_name)
    )


def filter_cdf_events(df: DataFrame) -> DataFrame:
    return df.filter(df._change_type.isin(["insert", "update_postimage"]))


def drop_partition_columns(df: DataFrame) -> DataFrame:
    columns_to_drop = ["year", "month", "day"]
    existing_columns = df.columns
    columns_to_remove = [col for col in columns_to_drop if col in existing_columns]

    if columns_to_remove:
        logger.info(f"Dropping partition columns: {columns_to_remove}")
        return df.drop(*columns_to_remove)

    return df


def check_delta_table_for_cdf(spark: SparkSession, table_name: str) -> None:
    """Validate that the Delta table exists and has CDF enabled."""
    table_exists = spark.catalog.tableExists(table_name)
    if not table_exists:
        raise ValueError(f"Table {table_name} does not exist")

    table_properties = spark.sql(f"DESCRIBE TABLE EXTENDED {table_name}").collect()

    cdf_enabled = any(
        "delta.enableChangeDataFeed" in str(row) and "true" in str(row).lower()
        for row in table_properties
    )

    if not cdf_enabled:
        raise ValueError(
            f"Change Data Feed is not enabled for table {table_name}. "
            f"Consider enabling it with: ALTER TABLE {table_name} "
            "SET TBLPROPERTIES (delta.enableChangeDataFeed = true)"
        )


class DeltaCDFToKafkaService:
    """Processes Delta Change Data Feed and publishes to Kafka."""

    def __init__(
        self,
        spark: SparkSession,
        delta_table: str,
        key_columns: List[str],
        kafka_options: Dict[str, Any],
        checkpoint_location: str,
    ):
        """
        Initialize the Delta CDF to Kafka processor.
        Args:
            spark: SparkSession instance
            delta_table: Full table name (database.table)
            kafka_options: Kafka options
            checkpoint_location: Checkpoint location for streaming (optional)
        """
        self.spark = spark
        self.delta_table = delta_table
        self.key_columns = key_columns
        self.checkpoint_location = checkpoint_location
        self.kafka_options = kafka_options

    def run(self) -> None:
        logger.info("Starting Delta CDF to Kafka processing")
        logger.info(f"Delta table: {self.delta_table}")
        logger.info(f"Kafka topic: {self.kafka_options['topic']}")
        logger.info(
            f"Kafka bootstrap servers: {self.kafka_options['kafka.bootstrap.servers']}"
        )

        listener = CDFToKafkaStreamListener()
        self.spark.streams.addListener(listener)

        check_delta_table_for_cdf(self.spark, self.delta_table)
        cdf = read_cdf_stream(self.spark, self.delta_table)
        logger.info("Filtering CDF events: insert and update_postimage only")
        filtered_cdf = filter_cdf_events(cdf)
        cleaned_cdf = drop_partition_columns(filtered_cdf)
        transformed_cdf = cdf_to_kafka_format(
            cleaned_cdf, self.key_columns, self.delta_table
        )

        write_to_kafka(transformed_cdf, self.kafka_options, self.checkpoint_location)
