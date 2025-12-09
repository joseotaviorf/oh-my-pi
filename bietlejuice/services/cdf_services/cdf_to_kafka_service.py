import logging
import time
from typing import Any, Dict, List, Optional

from pyspark.sql import DataFrame, SparkSession

from .cdf_to_kafka_config import config
from .cdf_transformations import (
    cdf_to_kafka_format,
    drop_partition_columns,
    filter_cdf_events,
)
from .kafka_stream_listener import CDFToKafkaStreamListener
from .schema_registry import register_schema_for_dataframe

logger = logging.getLogger(__name__)


class DeltaCDFToKafkaService:
    """Processes Delta Change Data Feed and publishes to Kafka with Schema Registry integration."""

    def __init__(
        self,
        spark: SparkSession,
        delta_table: str,
        key_columns: List[str],
        kafka_options: Dict[str, Any],
        checkpoint_location: str,
        entity: str,
        schema_registry_url: Optional[str] = None,
        schema_registry_api_key: Optional[str] = None,
        schema_registry_api_secret: Optional[str] = None,
    ):
        """
        Initialize the Delta CDF to Kafka processor.

        Args:
            spark: SparkSession instance
            delta_table: Full table name (database.table)
            key_columns: List of column names to use as Kafka key
            kafka_options: Kafka options including bootstrap servers, topic, and auth
            checkpoint_location: Checkpoint location for streaming state management
            schema_registry_url: URL for Confluent Schema Registry (optional when use_schema_registry=False)
            schema_registry_api_key: API key for Schema Registry authentication (optional when use_schema_registry=False)
            schema_registry_api_secret: API secret for Schema Registry authentication (optional when use_schema_registry=False)
            entity: Entity name
        Raises:
            ValueError: If Delta table does not exist or CDF is not enabled
        """
        self.spark = spark
        self.delta_table = delta_table
        self.key_columns = key_columns
        self.checkpoint_location = checkpoint_location
        self.kafka_options = kafka_options
        self.schema_registry_url = schema_registry_url
        self.schema_registry_api_key = schema_registry_api_key
        self.schema_registry_api_secret = schema_registry_api_secret
        self.schema_id: Optional[int] = None
        self.entity = entity

    def read_cdf_stream(self) -> DataFrame:
        """Read from Delta Change Data Feed as a streaming DataFrame."""
        return (
            self.spark.readStream.format("delta")
            .option("readChangeFeed", "true")
            .table(self.delta_table)
        )

    def check_delta_table_for_cdf(self) -> None:
        """Validate that the Delta table exists and has CDF enabled."""
        table_exists = self.spark.catalog.tableExists(self.delta_table)
        if not table_exists:
            raise ValueError(f"Table {self.delta_table} does not exist")

        table_properties = self.spark.sql(
            f"DESCRIBE TABLE EXTENDED {self.delta_table}"
        ).collect()

        cdf_enabled = any(
            "delta.enableChangeDataFeed" in str(row) and "true" in str(row).lower()
            for row in table_properties
        )

        if not cdf_enabled:
            raise ValueError(
                f"Change Data Feed is not enabled for table {self.delta_table}. "
                f"Consider enabling it with: ALTER TABLE {self.delta_table} "
                "SET TBLPROPERTIES (delta.enableChangeDataFeed = true)"
            )

    def write_to_kafka(self, df: DataFrame) -> None:
        """Write the transformed data to Kafka topic."""
        query = (
            df.writeStream.format("kafka")
            .options(**self.kafka_options)
            .option("checkpointLocation", self.checkpoint_location)
            .trigger(availableNow=True)
            .outputMode("append")
            .start()
        )

        logger.info(
            f"Started streaming to Kafka topic '{self.kafka_options['topic']}' "
        )
        logger.info(
            "Forcing the KafkaStreamListener to be called... (by sleeping for 30 seconds)"
        )
        time.sleep(30)

        query.awaitTermination()

    def run(self) -> None:
        """Execute the CDF to Kafka streaming pipeline."""
        logger.info("Starting Delta CDF to Kafka processing")
        logger.info(f"Delta table: {self.delta_table}")
        logger.info(f"Kafka topic: {self.kafka_options['topic']}")
        logger.info(
            f"Kafka bootstrap servers: {self.kafka_options['kafka.bootstrap.servers']}"
        )
        logger.info(f"Use Schema Registry: {config.use_schema_registry}")

        listener = CDFToKafkaStreamListener()
        self.spark.streams.addListener(listener)

        self.check_delta_table_for_cdf()

        cdf = self.read_cdf_stream()

        filtered_cdf = filter_cdf_events(cdf)

        cleaned_cdf = drop_partition_columns(filtered_cdf)

        self.schema_id = None
        if config.use_schema_registry:
            self.schema_id = register_schema_for_dataframe(
                dataframe=cleaned_cdf,
                topic=self.kafka_options["topic"],
                delta_table=self.delta_table,
                schema_registry_url=self.schema_registry_url,
                schema_registry_api_key=self.schema_registry_api_key,
                schema_registry_api_secret=self.schema_registry_api_secret,
            )

        transformed_cdf = cdf_to_kafka_format(
            cleaned_cdf,
            self.key_columns,
            self.delta_table,
            self.schema_id,
            self.entity,
            use_schema_registry=config.use_schema_registry,
        )

        self.write_to_kafka(transformed_cdf)
