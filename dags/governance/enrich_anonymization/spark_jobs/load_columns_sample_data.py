import ast
import logging
from argparse import ArgumentParser
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime
from typing import Dict, List, Optional

from pyspark.errors import AnalysisException
from pyspark.sql import DataFrame, Row
from pyspark.sql.types import (
    ArrayType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

DELTA_TABLE_NOT_FOUND = "DELTA_TABLE_NOT_FOUND"
TABLE_OR_VIEW_NOT_FOUND = "TABLE_OR_VIEW_NOT_FOUND"
INSUFFICIENT_PERMISSIONS = "INSUFFICIENT_PERMISSIONS"
JOB_NAME = "load_columns_sample_data"

logging.getLogger("py4j").setLevel(logging.ERROR)


class NoDataFoundException(Exception):
    """Raised when a column has no non-null sample values."""

    def __init__(self):
        self.message = "No Data Found. Verify if this is a table in use or if is not a unused old column"
        super().__init__(self.message)


def create_table_schema() -> StructType:
    return StructType(
        [
            StructField("id_entity", StringType(), nullable=True),
            StructField("layer", StringType(), nullable=True),
            StructField("database_name", StringType(), nullable=True),
            StructField("table_name", StringType(), nullable=True),
            StructField("column_name", StringType(), nullable=True),
            StructField(
                "sample", ArrayType(StringType(), containsNull=False), nullable=True
            ),
            StructField("status", StringType(), nullable=True),
            StructField("error_class", StringType(), nullable=True),
            StructField("error_message", StringType(), nullable=True),
            StructField("ts_ingested", TimestampType(), nullable=True),
        ]
    )


def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
    merge_on: Optional[list] = None,
) -> None:
    if merge_on is None:
        merge_on = []
    print("m=load_table,msg='loading table'")

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    loader = DeltaLoader()
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}/{table_name}",
        source_df=dataframe,
        merge_on=merge_on,
    )


def _column_non_null_predicate(column_name: str) -> str:
    return f"({column_name} IS NOT NULL AND CAST({column_name} AS STRING) != '')"


def _build_union_all_column_samples(
    columns: List[Row],
    database_name: str,
    table_name: str,
    partition_predicate: Optional[str],
) -> str:
    parts = []
    for col in columns:
        cname = col.column_name
        where_clause = _column_non_null_predicate(cname)
        if partition_predicate:
            where_clause = f"({partition_predicate}) AND ({where_clause})"
        parts.append(
            f"""SELECT '{cname}' AS column_name,
                   CAST({cname} AS STRING) AS column_value
            FROM {database_name}.{table_name}
            WHERE {where_clause}
            LIMIT 10"""
        )
    return " UNION ALL ".join(parts)


def create_query_to_sample_table(
    columns: List[Row],
    load_start_date: str,
    execution_date: datetime,
    partition_predicate: Optional[str],
) -> str:
    """Build one sampled row per column via UNION ALL + array_agg.

    partition_predicate: e.g. ``year = 2026 AND month = 5`` for recent partitions only,
    or ``None`` for a full table scan (per-branch LIMIT 10).
    """
    if not columns:
        raise ValueError("columns must be non-empty")

    first = columns[0].asDict()
    layer = first["layer"]
    database_name = first["database_name"]
    table_name = first["table_name"]

    union_sql = _build_union_all_column_samples(
        columns, database_name, table_name, partition_predicate
    )
    return f"""
        WITH combined AS ({union_sql})
        SELECT
            CONCAT('{database_name}', '.', '{table_name}', '.', column_name) AS id_entity,
            '{layer}' AS layer,
            '{database_name}' AS database_name,
            '{table_name}' AS table_name,
            column_name,
            array_agg(column_value) AS sample,
            'SUCCESS' AS status,
            CAST(NULL AS STRING) AS error_class,
            CAST(NULL AS STRING) AS error_message,
            to_timestamp('{load_start_date}') AS ts_ingested
        FROM combined
        GROUP BY column_name
    """


def _success_column_names(results: List[Dict]) -> set:
    return {r["column_name"] for r in results if r.get("status") == "SUCCESS"}


def get_columns_to_sample(
    spark_client: SparkClient, load_start_date: str, load_end_date: str
) -> DataFrame:
    sql = f"""
        WITH columns_datalake AS (
            SELECT
                CONCAT(database_name, ".", table_name, ".", column_name) AS id_entity,
                CASE
                    WHEN database_name = "sandbox" THEN "sandbox"
                    ELSE layer
                END AS layer,
                database_name,
                table_name,
                column_name
            FROM
                datalake_documentation_metrics_clean.columns_metastore
            WHERE
                MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
                AND (
                    layer in ('clean', 'enrich', 'dw')
                    OR database_name = "sandbox"
                )
            ),
            columns_to_sample AS (
            SELECT
                id_entity
            FROM
                datalake_anonymization.columns_sample_data
        )
        SELECT
            layer,
            database_name,
            table_name,
            column_name
        FROM
            columns_datalake AS cd
                LEFT JOIN columns_to_sample AS cts
                    ON cd.id_entity = cts.id_entity
        WHERE
            cts.id_entity IS NULL
    """
    return spark_client.get_records(sql)


def create_sample_error_register(
    column: Row, error: Exception, load_start_date: str
) -> Dict:
    dict_column = column.asDict()

    layer = dict_column["layer"]
    database_name = dict_column["database_name"]
    table_name = dict_column["table_name"]
    col_name = dict_column["column_name"]

    return {
        "id_entity": f"{database_name}.{table_name}.{col_name}",
        "layer": layer,
        "database_name": database_name,
        "table_name": table_name,
        "column_name": col_name,
        "sample": None,
        "status": "FAIL",
        "error_class": f"{error.__class__.__module__}.{error.__class__.__name__}",
        "error_message": str(error)[:300],
        "ts_ingested": datetime.strptime(load_start_date, "%Y-%m-%d"),
    }


def _log_analysis_exception(entity_id: str, exc: AnalysisException) -> None:
    error_class = exc.getErrorClass()
    if error_class in [DELTA_TABLE_NOT_FOUND, TABLE_OR_VIEW_NOT_FOUND]:
        logging.warning("Table %s not found.", entity_id)
    elif error_class in [INSUFFICIENT_PERMISSIONS]:
        logging.warning("Insufficient permission to read table %s.", entity_id)
    else:
        logging.warning(
            "Not handled error. Table: %s. Error: %s", entity_id, error_class
        )


def process_table(
    spark_client: SparkClient,
    columns: List[Row],
    execution_date: datetime,
    load_start_date: str,
    table_id: str,
) -> List[Dict]:
    if not columns:
        return []

    year_month_predicate = (
        f"year = {execution_date.year} AND month = {execution_date.month}"
    )

    def _rows_to_results(rows: List) -> List[Dict]:
        out = []
        for r in rows:
            row_dict = r.asDict()
            row_dict["ts_ingested"] = execution_date
            out.append(row_dict)
        return out

    def _collect_for_cols(cols: List[Row], partition_predicate: Optional[str]) -> List:
        sql = create_query_to_sample_table(
            cols, load_start_date, execution_date, partition_predicate
        )
        return spark_client.get_records(sql).collect()

    try:
        used_full_scan_for_all = False
        try:
            recent_rows = _collect_for_cols(columns, year_month_predicate)
        except AnalysisException as exc:
            error_class = exc.getErrorClass()
            if error_class in [
                DELTA_TABLE_NOT_FOUND,
                TABLE_OR_VIEW_NOT_FOUND,
                INSUFFICIENT_PERMISSIONS,
            ]:
                _log_analysis_exception(table_id, exc)
                return [
                    create_sample_error_register(col, exc, load_start_date)
                    for col in columns
                ]
            logging.warning(
                "Partition-pruned sample failed for %s; retrying full scan for "
                "all columns. Error: %s",
                table_id,
                error_class,
            )
            recent_rows = _collect_for_cols(columns, None)
            used_full_scan_for_all = True

        results = _rows_to_results(recent_rows)

        missing = [
            col
            for col in columns
            if col.column_name not in _success_column_names(results)
        ]
        if missing and not used_full_scan_for_all:
            try:
                full_rows = _collect_for_cols(missing, None)
                results.extend(_rows_to_results(full_rows))
            except AnalysisException as exc:
                _log_analysis_exception(table_id, exc)
                for col in missing:
                    results.append(
                        create_sample_error_register(col, exc, load_start_date)
                    )
            except Exception as exc:
                logging.warning(
                    "Exception on full-scan fallback for %s: %s",
                    table_id,
                    type(exc).__name__,
                )
                for col in missing:
                    results.append(
                        create_sample_error_register(col, exc, load_start_date)
                    )

        success = _success_column_names(results)
        fail_columns = {r["column_name"] for r in results if r.get("status") == "FAIL"}
        for col in columns:
            if col.column_name not in success and col.column_name not in fail_columns:
                results.append(
                    create_sample_error_register(
                        col, NoDataFoundException(), load_start_date
                    )
                )

        return results

    except AnalysisException as exc:
        _log_analysis_exception(table_id, exc)
        return [
            create_sample_error_register(col, exc, load_start_date) for col in columns
        ]
    except Exception as exc:
        logging.warning("Exception sampling table %s: %s", table_id, type(exc).__name__)
        return [
            create_sample_error_register(col, exc, load_start_date) for col in columns
        ]


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str)
    parser.add_argument("datalake_bucket", type=str)
    parser.add_argument("schema", type=str)
    parser.add_argument("table_name", type=str)
    parser.add_argument("load_start_date", type=str)
    parser.add_argument("load_end_date", type=str)
    parser.add_argument("partitions", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument("merge_on", type=str)
    parser.add_argument(
        "--max_workers",
        type=int,
        default=8,
        help="Concurrent table-level Spark queries from the driver (ThreadPoolExecutor).",
    )

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    schema = args.schema
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    execution_date = datetime.strptime(load_start_date, "%Y-%m-%d")
    partition_cols = ast.literal_eval(args.partitions)
    source = args.source
    merge_on = ast.literal_eval(args.merge_on)
    max_workers = args.max_workers

    config_service = ConfigurationService(source)
    skip_list = config_service.get_config("skip_list")

    spark_client = SparkClient()

    df_tables_to_sample = get_columns_to_sample(
        spark_client, load_start_date, load_end_date
    )
    list_columns_to_sample = df_tables_to_sample.collect()

    table_groups = {}
    for col in list_columns_to_sample:
        tid = f"{col.database_name}.{col.table_name}"
        if tid not in skip_list:
            table_groups.setdefault(tid, []).append(col)

    all_records = []
    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        futures = {
            executor.submit(
                process_table,
                spark_client,
                cols,
                execution_date,
                load_start_date,
                tid,
            ): tid
            for tid, cols in table_groups.items()
        }
        for future in as_completed(futures):
            all_records.extend(future.result())

    df_load_sample = spark_client.create_dataframe(
        all_records, schema=create_table_schema()
    )
    df_load_sample = (
        SparkDataFrameService()
        .input(df_load_sample)
        .create_year_month_day_columns_from_date(execution_date)
        .optimize_partitions_by_partition_columns(partition_cols)
        .output()
    )
    load_table(df_load_sample, env, datalake_bucket, schema, table_name, merge_on)
