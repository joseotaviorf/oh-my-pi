"""Delta CDF stream reading and validation."""

import logging
from typing import Optional, Tuple

from pyspark.sql import DataFrame, SparkSession

from bietlejuice.services.cdf_services.cdf_to_kafka.config import config
from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.common import (
    drop_partition_columns,
    filter_cdf_events,
)
from bietlejuice.services.cdf_services.schema_registry import (
    register_schema_for_dataframe,
)

logger = logging.getLogger(__name__)


class DeltaCDFReader:
    """Reads and validates Delta Change Data Feed streams."""

    def __init__(
        self,
        spark: SparkSession,
        delta_table: str,
        schema_registry_url: Optional[str] = None,
        schema_registry_api_key: Optional[str] = None,
        schema_registry_api_secret: Optional[str] = None,
    ):
        self.spark = spark
        self.delta_table = delta_table
        self.schema_registry_url = schema_registry_url
        self.schema_registry_api_key = schema_registry_api_key
        self.schema_registry_api_secret = schema_registry_api_secret

    def validate_table(self) -> None:
        """Validate that the Delta table exists and has CDF enabled."""
        if not self.spark.catalog.tableExists(self.delta_table):
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
                f"Enable it with: ALTER TABLE {self.delta_table} "
                "SET TBLPROPERTIES (delta.enableChangeDataFeed = true)"
            )

        logger.info(f"Validated Delta table {self.delta_table} has CDF enabled")

    def read_cdf_stream(self) -> DataFrame:
        """Read from Delta Change Data Feed as a streaming DataFrame."""
        return (
            self.spark.readStream.format("delta")
            .option("readChangeFeed", "true")
            .table(self.delta_table)
        )

    def prepare_cdf_stream(self, kafka_topic: str) -> Tuple[DataFrame, Optional[int]]:
        """
        Read, filter, clean CDF stream and optionally register schema.

        Returns:
            Tuple of (cleaned_dataframe, schema_id)
        """
        logger.info("Reading CDF stream...")
        cdf = self.read_cdf_stream()

        logger.info("Filtering and cleaning CDF events...")
        filtered_cdf = filter_cdf_events(cdf)
        cleaned_cdf = drop_partition_columns(filtered_cdf)

        schema_id = None
        if config.use_schema_registry:
            logger.info("Registering schema in Schema Registry...")
            schema_id = register_schema_for_dataframe(
                dataframe=cleaned_cdf,
                topic=kafka_topic,
                delta_table=self.delta_table,
                schema_registry_url=self.schema_registry_url,
                schema_registry_api_key=self.schema_registry_api_key,
                schema_registry_api_secret=self.schema_registry_api_secret,
            )
            logger.info(f"Schema registered with ID: {schema_id}")

        return cleaned_cdf, schema_id
