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
from typing import Any, Dict, List

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


def _initialize_spark() -> SparkSession:
    """Returns an active SparkSession, using EMR-specific factory when appropriate."""
    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        return create_emr_spark_session(JOB_NAME)
    return SparkSession.builder.getOrCreate()


def _fetch_with_id_expansion(
    spark: SparkSession,
    client: Any,
    loader: APIConfigurationLoader,
    id_expansion_config: Dict[str, Any],
    source_schema: str,
    endpoint: str,
    initial_params: Dict[str, Any],
) -> List[Dict[str, Any]]:
    """
    Fetches data from a per-entity endpoint by fanning out over IDs from a source table.

    For each entity ID, uses ``loader.create_paginator`` when the table declares pagination
    (e.g. ``page_per_page``), flattening all pages into one list with ``id_field`` on each row.
    Otherwise performs a single GET; dict envelopes are kept as one row per entity (with
    correlation_field or id_field injected) and list bodies are flattened.

    Args:
        spark: Active SparkSession used to read the source table.
        client: Authenticated BaseAPIClient.
        loader: Loader for the current table (builds paginators inside the fan-out).
        id_expansion_config: id_expansion YAML block with source_table, id_field,
            and param_name (query param) or path_param (URL path segment). Optional
            correlation_field names the JSON key used when stamping each response row
            with the fan-out entity id (defaults to id_field).
        source_schema: Raw metastore schema name (e.g. "oitchau").
        endpoint: API endpoint path.
        initial_params: Base query params (e.g. date filters) to merge with each call.

    Returns:
        Combined list of response dicts from all per-entity API calls.
    """
    from pyspark.sql import functions as F

    source_table = id_expansion_config["source_table"]
    id_field = id_expansion_config["id_field"]
    injection_key = id_expansion_config.get("correlation_field") or id_field
    path_param = id_expansion_config.get("path_param")
    param_name = id_expansion_config.get("param_name")

    if path_param and param_name:
        raise ValueError(
            "m=_fetch_with_id_expansion, msg=id_expansion must not set both "
            "'path_param' and 'param_name'; use one."
        )
    if not path_param and not param_name:
        raise ValueError(
            "m=_fetch_with_id_expansion, msg=id_expansion requires 'path_param' or 'param_name'."
        )

    full_table_name = f"datalake_{source_schema}_raw.{source_table}"
    LOGGER.info(
        "m=_fetch_with_id_expansion, source_table=%s msg=Reading entity IDs",
        full_table_name,
    )

    ids_df = (
        spark.table(full_table_name)
        .select(F.get_json_object(F.col("payload"), f"$.{id_field}").alias("_id_value"))
        .where(F.col("_id_value").isNotNull())
        .distinct()
    )
    ids = [row["_id_value"] for row in ids_df.collect()]

    LOGGER.info(
        "m=_fetch_with_id_expansion, count=%d msg=Entity IDs loaded, starting fan-out",
        len(ids),
    )

    all_results: List[Dict[str, Any]] = []
    failed = 0

    path_placeholder = "{" + path_param + "}" if path_param else ""

    for entity_id in ids:
        params = dict(initial_params)
        resolved_endpoint = endpoint
        if path_param:
            if path_placeholder not in endpoint:
                raise ValueError(
                    f"m=_fetch_with_id_expansion, msg=endpoint_path must contain "
                    f"placeholder '{path_placeholder}' when id_expansion.path_param is set."
                )
            resolved_endpoint = endpoint.replace(path_placeholder, str(entity_id))
        else:
            params[param_name] = entity_id

        try:
            paginator = loader.create_paginator(client, resolved_endpoint, params)
            if paginator:
                for page_rows in paginator.fetch_all():
                    for item in page_rows:
                        if isinstance(item, dict):
                            item[injection_key] = entity_id
                    all_results.extend(page_rows)
            else:
                response = client.get(resolved_endpoint, params=params)
                data = response.json() if hasattr(response, "json") else response

                if isinstance(data, dict):
                    meta = data.get("metadata")
                    if isinstance(meta, dict):
                        total_pages = meta.get("totalPages")
                        if (
                            isinstance(total_pages, (int, float))
                            and int(total_pages) > 1
                        ):
                            LOGGER.warning(
                                "m=_fetch_with_id_expansion, %s=%s, endpoint=%s, totalPages=%s "
                                "msg=Multiple pages returned but only the first page was fetched; "
                                "configure api_policies.pagination for this table.",
                                id_field,
                                entity_id,
                                resolved_endpoint,
                                total_pages,
                            )
                    data[injection_key] = entity_id
                    all_results.append(data)
                elif isinstance(data, list):
                    for item in data:
                        if isinstance(item, dict):
                            item[injection_key] = entity_id
                    all_results.extend(data)
        except Exception as exc:
            failed += 1
            LOGGER.warning(
                "m=_fetch_with_id_expansion, %s=%s, error=%s msg=Skipping entity after error",
                id_field,
                entity_id,
                exc,
            )

    LOGGER.info(
        "m=_fetch_with_id_expansion, total=%d, failed=%d msg=Fan-out complete",
        len(all_results),
        failed,
    )
    return all_results


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

    source_schema = workflow.get("custom_schema", dag_name)
    if source_schema and source_schema.startswith("dw_"):
        source_schema = source_schema.replace("dw_", "", 1)

    id_expansion_config = loader.get_id_expansion_config()

    if id_expansion_config:
        LOGGER.info(
            "m=main, table_name=%s msg=id_expansion configured, initializing Spark to read source IDs",
            args.table_name,
        )
        spark = _initialize_spark()
        all_results = _fetch_with_id_expansion(
            spark=spark,
            client=client,
            loader=loader,
            id_expansion_config=id_expansion_config,
            source_schema=source_schema,
            endpoint=endpoint,
            initial_params=initial_params,
        )
    else:
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

        spark = _initialize_spark()

    payload_column = loader.get_payload_column_name()
    LOGGER.info(
        "m=main, table_name=%s, total_records=%d, payload_column=%s msg=API fetch complete",
        args.table_name,
        len(all_results),
        payload_column,
    )

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
