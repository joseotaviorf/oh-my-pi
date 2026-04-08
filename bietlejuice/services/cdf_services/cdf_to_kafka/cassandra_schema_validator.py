"""Cassandra schema validation for CDF dataframes against S3-hosted schema files."""

import json
import logging
from typing import Set

from pyspark.sql import DataFrame, SparkSession

from bietlejuice.services.cdf_services.cdf_to_kafka.config import config
from bietlejuice.services.cdf_services.cdf_to_kafka.transformations.headers import (
    get_data_columns_from,
)

logger = logging.getLogger(__name__)

_S3_PREFIX = "cassandra-table-schema"
_PROD_BUCKET = "wonka.s3.data.quintoandar.com.br"
_FORNO_BUCKET = "wonka.s3.forno.data.quintoandar.com.br"
_DOCS_URL = (
    "https://backstage.apps.core-prd.habitat.zone/docs/default/system/"
    "quintoml/monorepo/wonka/00.overview/"
)


class CassandraSchemaMismatchError(Exception):
    """Raised when the CDF dataframe contains columns absent from the Cassandra schema."""


def _resolve_bucket() -> str:
    if config.environment == "prod":
        return _PROD_BUCKET
    return _FORNO_BUCKET


def _build_s3_path(entity: str) -> str:
    bucket = _resolve_bucket()
    return f"s3a://{bucket}/{_S3_PREFIX}/{entity}_applied.json"


def _read_json_from_s3(spark: SparkSession, path: str) -> dict:
    rows = spark.read.text(path).collect()
    raw = "\n".join(row.value for row in rows)
    return json.loads(raw)


def _extract_cassandra_columns(schema: dict, feature_set_name: str) -> Set[str]:
    columns = schema.get("columns", {})
    matched = {
        col_name
        for col_name, col_meta in columns.items()
        if col_meta.get("feature_set_origin") == feature_set_name
    }
    if not matched:
        raise CassandraSchemaMismatchError(
            f"No columns found in the Cassandra schema for feature set '{feature_set_name}'. "
            f"Verify that the feature set name is correct and that the schema file is up to date. "
            f"Check the docs: {_DOCS_URL}"
        )
    return matched


def validate_against_cassandra_schema(
    spark: SparkSession,
    dataframe: DataFrame,
    entity: str,
    feature_set_name: str,
) -> None:
    """Validate that the dataframe columns are a subset of the Cassandra schema columns.

    Reads the schema JSON from S3 (path derived from entity name), filters columns
    by feature_set_origin matching feature_set_name, and raises
    CassandraSchemaMismatchError if the dataframe contains columns absent from the
    Cassandra schema (which would indicate a missing Wonka migration).

    Args:
        spark: Active SparkSession used to read from S3.
        dataframe: Cleaned CDF DataFrame (after drop_partition_columns).
        entity: Entity name, used to locate the schema file ({entity}_applied.json).
        feature_set_name: Feature set name used to filter schema columns by
            feature_set_origin.

    Raises:
        CassandraSchemaMismatchError: If extra columns are found in the dataframe.
        pyspark.sql.utils.AnalysisException: If the schema file does not exist on S3.
    """
    path = _build_s3_path(entity)
    logger.info(
        f"Validating CDF schema against Cassandra schema file: {path} "
        f"(feature_set_name={feature_set_name})"
    )

    schema = _read_json_from_s3(spark, path)
    cassandra_columns = _extract_cassandra_columns(schema, feature_set_name)

    df_columns = set(get_data_columns_from(dataframe))
    extra_columns = df_columns - cassandra_columns

    if extra_columns:
        sorted_extra = sorted(extra_columns)
        raise CassandraSchemaMismatchError(
            f"Cassandra schema mismatch for entity '{entity}' "
            f"(feature set: '{feature_set_name}').\n"
            f"The following columns exist in the dataframe but are missing from the "
            f"Cassandra table schema:\n"
            f"  {sorted_extra}\n"
            f"This likely means a Wonka migration has not been applied.\n"
            f"Check the docs: {_DOCS_URL}"
        )

    logger.info(
        f"Cassandra schema validation passed for entity '{entity}' "
        f"(feature_set_name={feature_set_name}). "
        f"All {len(df_columns)} dataframe columns are present in the Cassandra schema."
    )
