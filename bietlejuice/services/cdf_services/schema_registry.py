import json
import logging
from typing import Any, Dict

import requests
from pyspark.sql import DataFrame
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.schema_builder import (
    generate_json_schema_from_dataframe,
)

logger = logging.getLogger(__name__)


def _create_session_with_retry() -> requests.Session:
    """Create requests session with retry logic for transient failures."""
    session = requests.Session()
    retry_strategy = Retry(
        total=3,
        backoff_factor=2,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["POST", "GET"],
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    return session


def create_or_get_schema_on_registry(
    schema: Dict[str, Any],
    subject: str,
    schema_registry_url: str,
    schema_registry_api_key: str,
    schema_registry_api_secret: str,
) -> int:
    """Register JSON Schema with Confluent Schema Registry and return schema ID.

    Includes retry logic for transient failures (429, 500, 502, 503, 504 status codes).
    """
    url = f"{schema_registry_url}/subjects/{subject}/versions"

    schema_payload = {"schemaType": "JSON", "schema": json.dumps(schema)}

    headers = {"Content-Type": "application/vnd.schemaregistry.v1+json"}

    auth = (schema_registry_api_key, schema_registry_api_secret)

    logger.info(f"Registering schema for subject: {subject}")

    session = _create_session_with_retry()

    try:
        response = session.post(
            url, json=schema_payload, headers=headers, auth=auth, timeout=10
        )

        if response.status_code in [200, 201]:
            schema_id = response.json()["id"]
            logger.info(f"Schema registered successfully with ID: {schema_id}")
            return schema_id
        else:
            logger.error(
                f"Failed to persist schema on registry: {response.status_code} - {response.text}"
            )
            raise Exception(
                f"Failed to persist schema on registry: {response.status_code} - {response.text}"
            )
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to connect to Schema Registry after retries: {e}")
        raise Exception(
            f"Failed to connect to Schema Registry at {schema_registry_url}: {e}"
        )


def register_schema_for_dataframe(
    dataframe: DataFrame,
    topic: str,
    delta_table: str,
    schema_registry_url: str,
    schema_registry_api_key: str,
    schema_registry_api_secret: str,
) -> int:
    """Register schema for a DataFrame with Schema Registry and return schema ID.

    Schema Registry automatically handles deduplication - if the schema is identical
    to an existing one, it returns the existing schema ID. If the schema differs,
    it validates compatibility and either registers a new version or rejects it.

    Uses delta_table name as part of the subject to allow multiple feature sets
    writing to the same topic with different schemas.

    Args:
        dataframe: DataFrame to extract schema from (should be cleaned of CDF metadata columns)
        topic: Kafka topic name
        delta_table: Delta table name (e.g., "wonka.house_main__latest")
        schema_registry_url: URL for Confluent Schema Registry
        schema_registry_api_key: API key for Schema Registry authentication
        schema_registry_api_secret: API secret for Schema Registry authentication

    Returns:
        Schema ID from Schema Registry (new or existing)
    """
    logger.info("Registering schema with Schema Registry")

    feature_set_name = delta_table.split(".")[-1].replace("__latest", "")
    subject = f"{topic}.{feature_set_name}-value"

    data_columns = [
        col
        for col in dataframe.columns
        if col not in ["_change_type", "_commit_version", "_commit_timestamp"]
    ]

    data_df = dataframe.select(data_columns)

    json_schema = generate_json_schema_from_dataframe(data_df, schema_name=topic)

    logger.debug(f"Generated JSON Schema: {json.dumps(json_schema, indent=2)}")

    schema_id = create_or_get_schema_on_registry(
        schema=json_schema,
        subject=subject,
        schema_registry_url=schema_registry_url,
        schema_registry_api_key=schema_registry_api_key,
        schema_registry_api_secret=schema_registry_api_secret,
    )

    logger.info(f"Using schema ID: {schema_id}")
    return schema_id
