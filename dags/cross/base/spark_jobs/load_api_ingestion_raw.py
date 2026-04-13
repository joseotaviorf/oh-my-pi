"""
Reusable Spark job for API Ingestion workflow.

Loads data from any REST API endpoint using declarative YAML configuration.
Uses APIConfigurationLoader to instantiate authentication, pagination, and
rate limiting at runtime based on the DAG declaration.

Uses the standard library :mod:`logging` for this workflow (aligned with
``declaration_loader`` and API configuration modules).
"""

import json
import logging
import time
from argparse import ArgumentParser, Namespace

from pyspark.sql import SparkSession

from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.base.api.configuration.declaration_loader import (
    load_api_ingestion_declaration,
    validate_api_ingestion_dag_name,
)
from bietlejuice.base.api.configuration.loader import APIConfigurationLoader
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import json_to_dataframe, insert_partitions
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader

JOB_NAME = "load_api_ingestion_raw"
LOGGER = logging.getLogger(__name__)


def parse_arguments() -> Namespace:
    """Parses command-line arguments for the API ingestion job."""
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="Environment (forno, prod)")
    parser.add_argument("datalake_bucket", help="Target S3 bucket")
    parser.add_argument("dag_name", help="DAG name (schema)")
    parser.add_argument("table_name", help="Table/endpoint name")
    parser.add_argument("execution_date", help="Execution date (YYYY-MM-DD)")
    parser.add_argument(
        "partitions",
        help="Partition columns (JSON list or comma-separated)",
    )
    parser.add_argument(
        "extraction_type",
        help="Extraction type (full, incremental)",
    )
    parser.add_argument("load_start_date", help="Start date (YYYY-MM-DD)")
    parser.add_argument("load_end_date", help="End date (YYYY-MM-DD)")
    return parser.parse_args()


def _resolve_partitions(partitions_arg: str) -> list:
    """Resolves partition columns from the argument."""
    raw = (partitions_arg or "").strip()
    if not raw:
        return ["year", "month", "day"]
    try:
        parsed = json.loads(raw.replace("'", '"'))
        if isinstance(parsed, list) and all(isinstance(p, str) for p in parsed):
            return [p.strip() for p in parsed if p.strip()]
    except json.JSONDecodeError:
        pass
    return [p.strip() for p in raw.split(",") if p.strip()] or [
        "year",
        "month",
        "day",
    ]


def main() -> None:
    """
    Main entry point for the API ingestion raw layer job.

    Loads the DAG declaration, instantiates the API client and paginator
    via APIConfigurationLoader, fetches all pages, and loads to raw layer.
    """
    args = parse_arguments()
    dag_name = validate_api_ingestion_dag_name(args.dag_name)

    LOGGER.info(
        "m=main, dag_name=%s, table_name=%s, load_start_date=%s, load_end_date=%s "
        "msg=Starting API ingestion job",
        dag_name,
        args.table_name,
        args.load_start_date,
        args.load_end_date,
    )

    LOGGER.info(
        "m=main, dag_name=%s msg=Loading DAG declaration",
        dag_name,
    )
    declaration = load_api_ingestion_declaration(dag_name)
    workflow = declaration.get("workflow", {})
    if workflow.get("type") != "api_ingestion":
        raise ValueError(
            f"DAG '{dag_name}' is not configured for api_ingestion workflow. "
            f"Found type: {workflow.get('type')}"
        )

    tables_customization = workflow.get("tables_customization", {})
    table_config = tables_customization.get(args.table_name)
    if not table_config:
        raise ValueError(
            f"Table '{args.table_name}' not found in tables_customization "
            f"for DAG '{dag_name}'"
        )

    workflow_config = {
        k: v
        for k, v in workflow.items()
        if k
        not in (
            "tables_customization",
            "layer",
            "type",
            "custom_schema",
            "has_hive_sync",
        )
    }

    rate_limiting = workflow_config.get("api_policies", {}).get("rate_limiting", {})
    initial_delay = rate_limiting.get("initial_delay_seconds", 0)
    if initial_delay > 0:
        LOGGER.info(
            "m=main, initial_delay_seconds=%d msg=Waiting before first API request",
            initial_delay,
        )
        time.sleep(initial_delay)
    else:
        LOGGER.info(
            "m=main msg=No initial delay configured, proceeding to API request",
        )

    LOGGER.info(
        "m=main, table_name=%s msg=Creating API client and loader",
        args.table_name,
    )
    loader = APIConfigurationLoader(workflow_config, table_config)
    client = loader.create_api_client()

    endpoint = loader.get_endpoint_path()
    initial_params = loader.get_initial_params(args.load_start_date, args.load_end_date)
    LOGGER.info(
        "m=main, endpoint=%s, params=%s msg=API request configuration",
        endpoint,
        initial_params,
    )

    paginator = loader.create_paginator(client, endpoint, initial_params)

    all_results = []
    if paginator:
        LOGGER.info(
            "m=main, table_name=%s msg=Fetching data with pagination",
            args.table_name,
        )
        page_num = 0
        for page_results in paginator.fetch_all():
            page_num += 1
            all_results.extend(page_results)
            LOGGER.info(
                "m=main, table_name=%s, page=%d, page_records=%d, total_records=%d "
                "msg=Page fetched",
                args.table_name,
                page_num,
                len(page_results),
                len(all_results),
            )
    else:
        LOGGER.info(
            "m=main, table_name=%s msg=Fetching single page (no pagination)",
            args.table_name,
        )
        response = client.get(endpoint, params=initial_params)
        data = response.json() if hasattr(response, "json") else response
        if isinstance(data, dict):
            results_path = table_config.get("results_response_path", "results")
            all_results = data.get(results_path, [])
            if not all_results and "data" in data:
                all_results = data.get("data", [])
            if not all_results and "content" in data:
                content = data.get("content")
                if isinstance(content, list):
                    all_results = content
        elif isinstance(data, list):
            all_results = data
        LOGGER.info(
            "m=main, table_name=%s, records=%d msg=Single page response received",
            args.table_name,
            len(all_results),
        )

    payload_column = loader.get_payload_column_name()
    LOGGER.info(
        "m=main, table_name=%s, total_records=%d, payload_column=%s msg=API fetch complete",
        args.table_name,
        len(all_results),
        payload_column,
    )

    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        spark = create_emr_spark_session(JOB_NAME)
    else:
        spark = SparkSession.builder.getOrCreate()
    if not all_results:
        LOGGER.warning(
            "m=main, table_name=%s msg=No data returned from API. " "Skipping load.",
            args.table_name,
        )
        return

    LOGGER.info(
        "m=main, table_name=%s msg=Converting JSON to Spark DataFrame",
        args.table_name,
    )
    df = json_to_dataframe(spark, all_results, raw_column_name=payload_column)

    date_column = loader.get_date_column_for_partitioning()
    if date_column:
        df = insert_partitions(df, date_column)
    else:
        df = insert_partitions(df)

    partition_cols = _resolve_partitions(args.partitions)
    LOGGER.info(
        "m=main, table_name=%s, partition_cols=%s, date_column=%s msg=Partitions configured",
        args.table_name,
        partition_cols,
        date_column,
    )

    source_schema = workflow.get("custom_schema", dag_name)
    if source_schema and source_schema.startswith("dw_"):
        source_schema = source_schema.replace("dw_", "", 1)

    raw_loader = RawLayerLoader(
        spark_client=SparkClient(),
        environment=args.environment,
        source=source_schema or dag_name,
        datalake_bucket=args.datalake_bucket,
        table_name=args.table_name.lower(),
        partition_cols=partition_cols,
        extraction_type=args.extraction_type,
    )
    LOGGER.info(
        "m=main, table_name=%s, source=%s, bucket=%s, extraction_type=%s "
        "msg=Loading to raw layer",
        args.table_name,
        source_schema or dag_name,
        args.datalake_bucket,
        args.extraction_type,
    )

    raw_loader.load_to_raw(df)

    LOGGER.info(
        "m=main, table_name=%s, records=%d msg=Successfully loaded to raw layer",
        args.table_name,
        len(all_results),
    )


if __name__ == "__main__":
    try:
        main()
    finally:
        try:
            if RuntimeDetector.is_emr():
                spark.stop()
        except NameError:
            pass
