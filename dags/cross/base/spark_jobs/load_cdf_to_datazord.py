#!/usr/bin/env python3
"""
Delta CDF to Kafka Streaming Script

This script reads from a Delta table's Change Data Feed (CDF) and publishes
the changes to a Kafka topic. It's designed to run as a triggered job when
the Delta table is updated.
"""

import argparse
import json
import logging
import os

from pyspark.sql import SparkSession

from bietlejuice.services.cdf_to_kafka_service import DeltaCDFToKafkaService

logger = logging.getLogger(__name__)


def parse_arguments():
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Stream Delta Change Data Feed to Kafka topic"
    )

    parser.add_argument(
        "--delta-table", required=True, help="Full Delta table name (database.table)"
    )

    parser.add_argument(
        "--key-columns", required=True, help="List of column names to use as primary keys, separated by commas"
    )

    parser.add_argument(
        "--kafka-topic", required=True, help="Kafka topic to publish to"
    )

    parser.add_argument(
        "--kafka-bootstrap-servers", required=True, help="Kafka bootstrap servers"
    )

    parser.add_argument(
        "--checkpoint-location",
        help="Checkpoint location for streaming (default: STREAM_CHECKPOINT_PATH env var)",
    )

    parser.add_argument(
        "--extra-metadata", required=False, default="{}", help="Extra metadata to be added to the payload"
    )

    return parser.parse_args()


def main():
    """Main entry point."""
    args = parse_arguments()

    spark = SparkSession.builder.getOrCreate()

    kafka_api_key = os.getenv("KAFKA_API_KEY")
    kafka_api_secret = os.getenv("KAFKA_API_SECRET")

    service = DeltaCDFToKafkaService(
        spark=spark,
        delta_table=args.delta_table,
        key_columns=args.key_columns.split(","),
        checkpoint_location=args.checkpoint_location,
        kafka_options={
            "kafka.bootstrap.servers": args.kafka_bootstrap_servers,
            "topic": args.kafka_topic,
            "kafka.security.protocol": "SASL_SSL",
            "kafka.sasl.mechanism": "PLAIN",
            "kafka.sasl.jaas.config": f'org.apache.kafka.common.security.plain.PlainLoginModule required username="{kafka_api_key}" password="{kafka_api_secret}";',
        },
    )

    service.run()


if __name__ == "__main__":
    main()
