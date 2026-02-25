"""
Ingests Degreed API data by performing one GET per ID from a list.

IDs are read from a Spark table (e.g. datalake_degreed_clean.pathways).
Use for endpoints that return a single resource by ID (e.g. GET /pathways/{id}).
"""

import re

from bietlejuice.clients.db_clients import SparkClient
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql import SparkSession
from bietlejuice.base.spark import BaseDBUtils

from bietlejuice.jobs.degreed.argument_parser import JobArgumentParser
from bietlejuice.jobs.degreed.degreed_api import DegreedAPI
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader
from bietlejuice.jobs.common.helpers import json_to_dataframe

LOGGER = QuintoAndarLogger(__name__)

SAFE_ID_PATTERN = re.compile(r"^[a-zA-Z0-9_-]+$")

IDS_SOURCE_DATABASE_KEY = "ids_source_database"
IDS_SOURCE_TABLE_KEY = "ids_source_table"
ID_COLUMN_KEY = "id_column"
SCOPE_KEY = "scope"


def main():
    try:
        job_args = JobArgumentParser.parse_args()
        _validate_ids_source(job_args)
        LOGGER.info(f"Running from-id-list ingestion with arguments: {job_args}")

        spark = SparkSession.builder.getOrCreate()
        spark_client = SparkClient()
        base_dbutils = BaseDBUtils()
        base_dbutils.get_dbutils()

        ids = _get_ids_from_table(
            spark,
            job_args[IDS_SOURCE_DATABASE_KEY],
            job_args[IDS_SOURCE_TABLE_KEY],
            job_args.get(ID_COLUMN_KEY, "id"),
        )
        if not ids:
            LOGGER.warning(
                "No IDs returned from ids source table. No data will be loaded."
            )
            return

        LOGGER.info(
            f"Fetched {len(ids)} IDs from "
            f"{job_args[IDS_SOURCE_DATABASE_KEY]}.{job_args[IDS_SOURCE_TABLE_KEY]}"
        )

        ids_safe = _filter_safe_ids(ids)
        if len(ids_safe) < len(ids):
            LOGGER.warning(
                "Dropped %s invalid ID(s) (allowed: alphanumeric, hyphen, underscore)",
                len(ids) - len(ids_safe),
            )
        if not ids_safe:
            LOGGER.warning("No valid IDs to fetch. No data will be loaded.")
            return

        api_client = DegreedAPI(job_args)
        api_data_list = api_client.get_by_ids(ids_safe)

        if api_data_list:
            df = json_to_dataframe(spark, api_data_list)
            raw_loader = RawLayerLoader(
                spark_client=spark_client,
                environment=job_args["environment"],
                source=job_args["dag_name"],
                datalake_bucket=job_args["datalake_bucket"],
                table_name=job_args["table_name"],
                partition_cols=job_args["partition_cols"],
                extraction_type=job_args["extraction_type"],
            )
            raw_loader.load_to_raw(df)
            LOGGER.info(
                f"Loaded {len(api_data_list)} records into raw table "
                f"{job_args['table_name']}"
            )
        else:
            LOGGER.warning(
                "No data returned from the API for the given IDs. "
                "No data will be loaded."
            )

    except Exception as e:
        LOGGER.error(
            f"Unhandled error during from-id-list job execution: {e}", exc_info=True
        )
        raise


def _filter_safe_ids(ids: list[str]) -> list[str]:
    """Keep only IDs that are safe for URL path (SSRF mitigation)."""
    return [
        i for i in ids if isinstance(i, str) and i.strip() and SAFE_ID_PATTERN.match(i)
    ]


def _validate_ids_source(job_args: dict) -> None:
    if not job_args.get(IDS_SOURCE_DATABASE_KEY) or not job_args.get(
        IDS_SOURCE_TABLE_KEY
    ):
        raise ValueError(
            "From-id-list ingestion requires extra_details to include "
            f"'{IDS_SOURCE_DATABASE_KEY}' and '{IDS_SOURCE_TABLE_KEY}' "
            "(e.g. datalake_degreed_clean and pathways)."
        )
    if not job_args.get(SCOPE_KEY):
        raise ValueError(
            "From-id-list ingestion requires extra_details to include "
            "'scope' (e.g. pathways:read)."
        )


def _get_ids_from_table(
    spark: SparkSession, database: str, table: str, id_column: str
) -> list[str]:
    full_table_name = f"{database}.{table}"
    LOGGER.info(f"Reading IDs from {full_table_name}, column {id_column}")
    df = spark.table(full_table_name).select(id_column).distinct()
    rows = df.collect()
    return [
        str(getattr(row, id_column))
        for row in rows
        if getattr(row, id_column) is not None
    ]


if __name__ == "__main__":
    main()
