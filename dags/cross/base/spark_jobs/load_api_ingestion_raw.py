"""
Reusable Spark job for API Ingestion workflow.

Loads data from any REST API endpoint using declarative YAML configuration.
Uses APIConfigurationLoader to instantiate authentication, pagination, and
rate limiting at runtime based on the DAG declaration.

Uses the standard library :mod:`logging` for this workflow (aligned with
``declaration_loader`` and API configuration modules).
"""

import itertools
import json
import logging
import time
from argparse import ArgumentParser, Namespace
from concurrent.futures import FIRST_COMPLETED, ThreadPoolExecutor, wait
from datetime import date, timedelta
from threading import Lock
from typing import Any, Dict, List, Optional, Tuple

from pyspark.sql import SparkSession

from bietlejuice.base.api.configuration.declaration_loader import (
    load_api_ingestion_declaration,
    validate_api_ingestion_dag_name,
)
from bietlejuice.base.api.configuration.loader import APIConfigurationLoader
from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import insert_partitions, json_to_dataframe
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
    parser.add_argument(
        "-tdn",
        "--target-database-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    parser.add_argument(
        "-ttn",
        "--target-table-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
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


def _dates_previous_and_current_calendar_month(anchor_iso: str) -> List[str]:
    """
    Returns inclusive ISO dates from the first day of the previous calendar month
    through the anchor date.
    """
    anchor = date.fromisoformat(anchor_iso)
    if anchor.month == 1:
        range_start = date(anchor.year - 1, 12, 1)
    else:
        range_start = date(anchor.year, anchor.month - 1, 1)
    dates_out: List[str] = []
    cursor = range_start
    while cursor <= anchor:
        dates_out.append(cursor.isoformat())
        cursor += timedelta(days=1)
    return dates_out


def _dates_last_n_days(anchor_iso: str, days: int) -> List[str]:
    """
    Returns inclusive ISO dates for the last ``days`` calendar days ending on the anchor.

    Example: anchor 2026-07-26 and days=45 → 2026-06-12 through 2026-07-26 (45 values).
    """
    if days < 1:
        raise ValueError(
            f"m=_dates_last_n_days, days={days} msg=days must be >= 1 for last_n_days strategy"
        )
    anchor = date.fromisoformat(anchor_iso)
    range_start = anchor - timedelta(days=days - 1)
    dates_out: List[str] = []
    cursor = range_start
    while cursor <= anchor:
        dates_out.append(cursor.isoformat())
        cursor += timedelta(days=1)
    return dates_out


def _format_date_expansion_value(iso_date: str, date_format: Optional[str]) -> str:
    """
    Formats an expanded calendar date the same way ``get_initial_params`` would.

    Args:
        iso_date: Date in ``YYYY-MM-DD``.
        date_format: Optional strftime pattern from table/workflow ``date_format``.
            When omitted, uses ISO-8601 with a start-of-day suffix (same default
            family as ``APIConfigurationLoader.get_initial_params``).

    Returns:
        Formatted date string for the query param.
    """
    if date_format:
        return date.fromisoformat(iso_date).strftime(date_format)
    return f"{iso_date}T00:00:00.000Z"


def _resolve_date_expansion_values(
    date_expansion_config: Optional[Dict[str, Any]],
    load_start_date: str,
    load_end_date: str,
) -> List[Optional[str]]:
    """
    Resolves which values to assign to the date query param for each fan-out call.

    Returns a list of ISO date strings (``YYYY-MM-DD``), or ``[None]`` when no date
    expansion is configured (single request per entity using ``initial_params`` only).
    Callers that inject into HTTP params should pass values through
    ``_format_date_expansion_value`` when a ``date_format`` is configured.
    """
    if not date_expansion_config:
        return [None]

    strategy = date_expansion_config.get("strategy")
    anchor_key = date_expansion_config.get("anchor", "load_end_date")
    if anchor_key not in ("load_end_date", "load_start_date"):
        raise ValueError(
            "m=_resolve_date_expansion_values, "
            f"anchor={anchor_key!r} msg=date_expansion.anchor must be "
            "'load_end_date' or 'load_start_date'"
        )
    anchor_iso = load_end_date if anchor_key == "load_end_date" else load_start_date

    if strategy == "previous_and_current_calendar_month":
        return _dates_previous_and_current_calendar_month(anchor_iso)

    if strategy == "last_n_days":
        days_raw = date_expansion_config.get("days")
        if days_raw is None:
            raise ValueError(
                "m=_resolve_date_expansion_values, strategy=last_n_days "
                "msg=date_expansion.days is required"
            )
        return _dates_last_n_days(anchor_iso, int(days_raw))

    raise ValueError(
        f"m=_resolve_date_expansion_values, strategy={strategy!r} "
        "msg=Unsupported date_expansion strategy"
    )


def _warn_if_unpaginated_multi_page(
    data: Any,
    *,
    id_field: str,
    entity_id: str,
    endpoint: str,
) -> None:
    """Log when the API signals multiple pages but no paginator is configured."""
    if not isinstance(data, dict):
        return
    meta = data.get("metadata")
    if not isinstance(meta, dict):
        return
    total_pages = meta.get("totalPages")
    if isinstance(total_pages, (int, float)) and int(total_pages) > 1:
        LOGGER.warning(
            "m=_fetch_one_entity, %s=%s, endpoint=%s, totalPages=%s "
            "msg=Multiple pages returned but only the first page was fetched; "
            "configure api_policies.pagination for this table.",
            id_field,
            entity_id,
            endpoint,
            total_pages,
        )


def _fetch_one_entity(
    client: Any,
    loader: APIConfigurationLoader,
    id_expansion_config: Dict[str, Any],
    endpoint: str,
    initial_params: Dict[str, Any],
    entity_id: str,
    date_param_name: Optional[str],
    date_param_value: Optional[str],
) -> Tuple[List[Dict[str, Any]], bool]:
    """
    Performs one fan-out HTTP call for a single entity (and optional date override).

    Returns:
        Tuple of (result rows, success flag).
    """
    injection_key = (
        id_expansion_config.get("correlation_field") or id_expansion_config["id_field"]
    )
    path_param = id_expansion_config.get("path_param")
    param_name = id_expansion_config.get("param_name")
    json_body_field = id_expansion_config.get("json_body_field")

    params = dict(initial_params)
    if date_param_name and date_param_value is not None:
        params[date_param_name] = date_param_value

    resolved_endpoint = endpoint
    if path_param:
        path_placeholder = "{" + path_param + "}"
        if path_placeholder not in endpoint:
            raise ValueError(
                f"m=_fetch_one_entity, msg=endpoint_path must contain "
                f"placeholder '{path_placeholder}' when id_expansion.path_param is set."
            )
        resolved_endpoint = endpoint.replace(path_placeholder, str(entity_id))
    elif param_name:
        params[param_name] = entity_id

    if json_body_field:
        paginator = loader.create_paginator(client, resolved_endpoint, params)
        if paginator:
            raise ValueError(
                "m=_fetch_one_entity, msg=id_expansion.json_body_field "
                "(POST fan-out) does not support api_policies.pagination on this table."
            )

    rows: List[Dict[str, Any]] = []

    if json_body_field:
        response = client.post(
            resolved_endpoint,
            params=params,
            json={json_body_field: entity_id},
        )
        data = response.json() if hasattr(response, "json") else response
    else:
        paginator = loader.create_paginator(client, resolved_endpoint, params)
        if paginator:
            for page_rows in paginator.fetch_all():
                for item in page_rows:
                    if isinstance(item, dict):
                        item[injection_key] = entity_id
                rows.extend(page_rows)
            return rows, True

        response = client.get(resolved_endpoint, params=params)
        data = response.json() if hasattr(response, "json") else response

    if isinstance(data, dict):
        content = data.get("content")
        if isinstance(content, list):
            for item in content:
                if isinstance(item, dict):
                    item[injection_key] = entity_id
            rows.extend(content)
        else:
            _warn_if_unpaginated_multi_page(
                data,
                id_field=id_expansion_config["id_field"],
                entity_id=entity_id,
                endpoint=resolved_endpoint,
            )
            data[injection_key] = entity_id
            rows.append(data)
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                item[injection_key] = entity_id
        rows.extend(data)

    return rows, True


def _fetch_with_id_expansion(
    spark: SparkSession,
    client: Any,
    loader: APIConfigurationLoader,
    id_expansion_config: Dict[str, Any],
    source_schema: str,
    endpoint: str,
    initial_params: Dict[str, Any],
    load_start_date: str,
    load_end_date: str,
    date_expansion_config: Optional[Dict[str, Any]] = None,
    date_format: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """
    Fetches data from a per-entity endpoint by fanning out over IDs from a source table.

    For each entity ID, uses ``loader.create_paginator`` when the table declares pagination
    (e.g. ``page_per_page``), flattening all pages into one list with ``id_field`` on each row.
    Otherwise performs a single GET, or POST with a JSON body when ``json_body_field`` is set;
    dict envelopes are kept as one row per entity (with correlation_field or id_field injected)
    unless the response dict exposes a ``content`` list (then one row per list element).
    List bodies are flattened similarly to GET.

    Optional ``date_expansion`` repeats each entity call for multiple ``date`` (or other) param
    values. Optional ``max_workers`` on ``id_expansion`` parallelizes HTTP calls.

    Args:
        spark: Active SparkSession used to read the source table.
        client: Authenticated BaseAPIClient.
        loader: Loader for the current table (builds paginators inside the fan-out).
        id_expansion_config: id_expansion YAML block with source_table, id_field,
            and exactly one of param_name (query param), path_param (URL path segment),
            or json_body_field (JSON body key for POST, one request per entity). Optional
            correlation_field names the JSON key used when stamping each response row
            with the fan-out entity id (defaults to id_field).
        source_schema: Raw metastore schema name (e.g. "oitchau").
        endpoint: API endpoint path.
        initial_params: Base query params (e.g. date filters) to merge with each call.
        load_start_date: DAG load window start (YYYY-MM-DD).
        load_end_date: DAG load window end (YYYY-MM-DD).
        date_expansion_config: Optional table-level date_expansion block.
        date_format: Optional strftime pattern from table/workflow ``date_format``;
            applied to each expanded date before HTTP injection.

    Returns:
        Combined list of response dicts from all per-entity API calls.
    """
    from pyspark.sql import functions as F
    from pyspark.sql.window import Window

    source_table = id_expansion_config["source_table"]
    id_field = id_expansion_config["id_field"]
    path_param = id_expansion_config.get("path_param")
    param_name = id_expansion_config.get("param_name")
    json_body_field = id_expansion_config.get("json_body_field")

    expansion_modes = sum(bool(x) for x in (path_param, param_name, json_body_field))
    if expansion_modes != 1:
        raise ValueError(
            "m=_fetch_with_id_expansion, msg=id_expansion requires exactly one of "
            "'path_param', 'param_name', or 'json_body_field'."
        )

    if json_body_field:
        paginator = loader.create_paginator(client, endpoint, dict(initial_params))
        if paginator:
            raise ValueError(
                "m=_fetch_with_id_expansion, msg=id_expansion.json_body_field "
                "(POST fan-out) does not support api_policies.pagination on this table."
            )

    if path_param:
        path_placeholder = "{" + path_param + "}"
        if path_placeholder not in endpoint:
            raise ValueError(
                "m=_fetch_with_id_expansion, msg=endpoint_path must contain "
                f"placeholder '{path_placeholder}' when id_expansion.path_param is set."
            )

    date_values = _resolve_date_expansion_values(
        date_expansion_config, load_start_date, load_end_date
    )
    date_param_name = None
    if date_expansion_config:
        date_param_name = date_expansion_config.get("param_name")
        if not date_param_name:
            raise ValueError(
                "m=_fetch_with_id_expansion, msg=date_expansion.param_name is required "
                "when date_expansion is configured"
            )
        date_values = [
            None if value is None else _format_date_expansion_value(value, date_format)
            for value in date_values
        ]

    if (
        "max_workers" not in id_expansion_config
        or id_expansion_config.get("max_workers") is None
    ):
        max_workers = 1
    else:
        max_workers = int(id_expansion_config["max_workers"])
    if max_workers < 1:
        raise ValueError("m=_fetch_with_id_expansion, msg=max_workers must be >= 1")

    full_table_name = f"datalake_{source_schema}_raw.{source_table}"
    LOGGER.info(
        "m=_fetch_with_id_expansion, source_table=%s msg=Reading entity IDs",
        full_table_name,
    )

    ids_df = spark.table(full_table_name)
    id_col = F.get_json_object(F.col("payload"), f"$.{id_field}")
    latest_per_entity = Window.partitionBy(id_col).orderBy(
        F.col("ts_load").desc_nulls_last(),
        F.col("year").desc_nulls_last(),
        F.col("month").desc_nulls_last(),
        F.col("day").desc_nulls_last(),
    )
    ids_df = (
        ids_df.withColumn("_fanout_id", id_col)
        .where(F.col("_fanout_id").isNotNull())
        .withColumn("_fanout_rn", F.row_number().over(latest_per_entity))
        .where(F.col("_fanout_rn") == 1)
    )

    payload_filters = id_expansion_config.get("payload_filters") or []
    if isinstance(payload_filters, dict):
        payload_filters = [payload_filters]
    if not isinstance(payload_filters, list):
        raise ValueError(
            "m=_fetch_with_id_expansion, msg=payload_filters must be a list of "
            "{field, equals} maps (a single map is also accepted)"
        )
    for payload_filter in payload_filters:
        if not isinstance(payload_filter, dict):
            raise ValueError(
                "m=_fetch_with_id_expansion, msg=each payload_filters entry must be a map"
            )
        field_name = payload_filter.get("field") or payload_filter.get("json_path")
        if not field_name:
            raise ValueError(
                "m=_fetch_with_id_expansion, msg=payload_filters entry requires 'field'"
            )
        if "equals" not in payload_filter:
            raise ValueError(
                "m=_fetch_with_id_expansion, msg=payload_filters entry requires 'equals'"
            )
        json_path = f"$.{field_name}"
        column_expr = F.get_json_object(F.col("payload"), json_path)
        expected = payload_filter["equals"]
        if isinstance(expected, bool):
            ids_df = ids_df.where(column_expr == str(expected).lower())
        elif expected is None:
            ids_df = ids_df.where(column_expr.isNull())
        else:
            ids_df = ids_df.where(column_expr == str(expected))

    ids_df = ids_df.select(F.col("_fanout_id").alias("_id_value")).distinct()
    ids = [row["_id_value"] for row in ids_df.collect()]

    total_tasks = len(ids) * len(date_values)
    LOGGER.info(
        "m=_fetch_with_id_expansion, entities=%d, date_values=%d, tasks=%d, "
        "max_workers=%d msg=Entity IDs loaded, starting fan-out",
        len(ids),
        len(date_values),
        total_tasks,
        max_workers,
    )

    all_results: List[Dict[str, Any]] = []
    results_lock = Lock() if max_workers > 1 else None
    failed = 0
    id_field_log = id_expansion_config["id_field"]

    def _run_task(task: Tuple[str, Optional[str]]) -> Tuple[List[Dict[str, Any]], bool]:
        entity_id, date_value = task
        try:
            return _fetch_one_entity(
                client=client,
                loader=loader,
                id_expansion_config=id_expansion_config,
                endpoint=endpoint,
                initial_params=initial_params,
                entity_id=entity_id,
                date_param_name=date_param_name,
                date_param_value=date_value,
            )
        except Exception as exc:
            LOGGER.warning(
                "m=_fetch_with_id_expansion, %s=%s, date=%s, error=%s "
                "msg=Skipping entity after error",
                id_field_log,
                entity_id,
                date_value,
                exc,
            )
            return [], False

    tasks: List[Tuple[str, Optional[str]]] = [
        (entity_id, date_value) for entity_id in ids for date_value in date_values
    ]

    if max_workers == 1:
        for task in tasks:
            rows, ok = _run_task(task)
            if ok:
                all_results.extend(rows)
            else:
                failed += 1
    else:
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            task_iter = iter(tasks)
            pending = {
                executor.submit(_run_task, task)
                for task in itertools.islice(task_iter, max_workers)
            }
            while pending:
                done, pending = wait(pending, return_when=FIRST_COMPLETED)
                for future in done:
                    rows, ok = future.result()
                    if ok:
                        if results_lock:
                            with results_lock:
                                all_results.extend(rows)
                        else:
                            all_results.extend(rows)
                    else:
                        failed += 1
                    try:
                        next_task = next(task_iter)
                    except StopIteration:
                        continue
                    pending.add(executor.submit(_run_task, next_task))

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
    date_expansion_config = table_config.get("date_expansion")
    table_date_format = table_config.get("date_format")
    if table_date_format == "":
        raise ValueError(
            "date_format cannot be an empty string. "
            "Use ISO-8601 format by omitting date_format or specify a valid strftime format."
        )
    date_format = (
        table_date_format
        if table_date_format
        else workflow_config.get("date_format")
        or workflow_config.get("date_format_mask")
    )

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
            load_start_date=args.load_start_date,
            load_end_date=args.load_end_date,
            date_expansion_config=date_expansion_config,
            date_format=date_format,
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
            "m=main, table_name=%s msg=No data returned from API. Skipping load.",
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
    if args.target_database_name and args.target_table_name:
        from bietlejuice.base.validation.target_resolver import (
            validation_database_location,
        )

        prod_database_name = raw_loader.database_name
        write_table_name = args.target_table_name
        raw_loader.database_name = args.target_database_name
        raw_loader.table_name = write_table_name
        raw_loader.database_location = validation_database_location(
            args.datalake_bucket, prod_database_name
        ).replace("s3a://", "s3://")

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
    from bietlejuice.base.spark.spark_session_factory import run_spark_entrypoint

    run_spark_entrypoint(main)
