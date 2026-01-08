"""Main orchestrator for Delta CDF to Kafka pipeline."""

import logging
from typing import Any, Dict, List, Optional

from pyspark.sql import SparkSession

from bietlejuice.services.cdf_services.cdf_to_kafka.config import config
from bietlejuice.services.cdf_services.cdf_to_kafka.metrics.metrics_publisher import (
    CDFToKafkaMetricsPublisher,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.stream_reader import DeltaCDFReader
from bietlejuice.services.cdf_services.cdf_to_kafka.stream_writer import (
    KafkaStreamWriter,
)
from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.common import (
    cdf_to_kafka_format,
)

logger = logging.getLogger(__name__)


class DeltaCDFToKafkaService:
    """
    Processes Delta Change Data Feed and publishes to Kafka with Schema Registry integration.
    Optimized for short-lived batch jobs with proper metrics handling.
    """

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
            entity: Entity name
            schema_registry_url: URL for Confluent Schema Registry
            schema_registry_api_key: API key for Schema Registry authentication
            schema_registry_api_secret: API secret for Schema Registry authentication
        """
        self.spark = spark
        self.delta_table = delta_table
        self.key_columns = key_columns
        self.checkpoint_location = checkpoint_location
        self.kafka_options = kafka_options
        self.entity = entity

        table_name = self.delta_table.split(".")[-1]
        self.feature_set_name = table_name.replace("__latest", "")

        self.reader = DeltaCDFReader(
            spark=spark,
            delta_table=delta_table,
            schema_registry_url=schema_registry_url,
            schema_registry_api_key=schema_registry_api_key,
            schema_registry_api_secret=schema_registry_api_secret,
        )

        self.metrics_publisher = CDFToKafkaMetricsPublisher(
            entity=self.entity,
            feature_set_name=self.feature_set_name,
        )

        self.writer = KafkaStreamWriter(
            checkpoint_location=checkpoint_location,
            kafka_options=kafka_options,
            metrics_publisher=self.metrics_publisher,
        )

    def run(self) -> None:
        """Execute the CDF to Kafka streaming pipeline."""
        self._log_start()

        self.reader.validate_table()

        cleaned_cdf, schema_id = self.reader.prepare_cdf_stream(
            kafka_topic=self.kafka_options["topic"]
        )

        transformed_cdf = cdf_to_kafka_format(
            cdf_dataframe=cleaned_cdf,
            key_columns=self.key_columns,
            source_table=self.delta_table,
            schema_id=schema_id,
            entity=self.entity,
            use_schema_registry=config.use_schema_registry,
        )

        self.writer.write_to_kafka(df=transformed_cdf)

        self._log_completion()

    def _log_start(self) -> None:
        """Log pipeline start information."""
        logger.info("=" * 80)
        logger.info("Starting Delta CDF to Kafka processing")
        logger.info(f"Delta table: {self.delta_table}")
        logger.info(f"Feature set: {self.feature_set_name}")
        logger.info(f"Entity: {self.entity}")
        logger.info(f"Kafka topic: {self.kafka_options['topic']}")
        logger.info(
            f"Kafka bootstrap servers: {self.kafka_options['kafka.bootstrap.servers']}"
        )
        logger.info(f"Use Schema Registry: {config.use_schema_registry}")
        logger.info(f"Checkpoint location: {self.checkpoint_location}")
        logger.info("=" * 80)

    def _log_completion(self) -> None:
        """Log pipeline completion."""
        logger.info("=" * 80)
        logger.info("Delta CDF to Kafka processing completed successfully")
        logger.info("=" * 80)
