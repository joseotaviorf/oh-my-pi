"""
This spark job receives the inference-status snapshot Task A
(stage_inference_status_to_s3 in ../vocs_machina_planning.py) published via
XCom as a JSON string -- one row set per DAG run, covering every active
prompt's whole backfill window as of that run -- and registers it as
datalake_vocs_machina_planning_raw.vocs_machina_inference_status.

The rows arrive as this job's last CLI parameter (the DAG templates it via
`{{ ti.xcom_pull(task_ids='stage-inference-status-to-s3', key='...') }}`)
rather than a staged S3 object: airflow-prod-role has no S3 write grant on
this repo's own datalake bucket, only Databricks' instance profile does, so
Task A hands the rows to this job through Airflow's own XCom store instead.

Shape otherwise mirrors dags/platform/dag_inventory/spark_jobs/load_dag_inventory_raw.py:
build a Spark DataFrame from the rows, then S3Loader.load_df +
SparkMetastoreLoader.update_metastore + SparkMetastoreService.create_new_partitions_from_df.

Partitioning: year/month/day are parsed from each row's own "day" field (the
backfill day whose inference status the row reports) and reused as BOTH the
partition columns and the only surviving representation of that day -- no
separate date column, matching load_dag_inventory_raw.py's
create_dag_dataframe (which also has no date column beyond year/month/day).
This is deliberately different from load_start_date (this DAG run's own
ingestion/load date, passed separately for logging): a single published row
set mixes many different backfill days across all active prompts, so "the
day this snapshot was taken" and "the day a given row's status is about" are
genuinely different things. Only the latter is used for this table's
partitions, so the raw table stays queryable per backfill day (same idea as
load_vocs_machina_raw.py, which partitions by the day its content is about).
"""

import json
import logging
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql import Row
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_vocs_machina_inference_status_raw"
DATE_FMT = "%Y-%m-%d"
INFERENCE_STATUS_SCHEMA = (
    "prompt_id:string, prompt_hash:string, inference_status:string, "
    "year:int, month:int, day:int"
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def build_inference_status_dataframe(rows: list):
    """Transform the published inference-status rows into a Spark DataFrame.

    Uses the bare global `spark` SparkSession, matching
    load_dag_inventory_raw.py's create_dag_dataframe -- Databricks injects
    `spark` into the execution namespace of spark_python_task jobs.

    Passes an explicit schema (same pattern as create_dag_dataframe), since
    spark.createDataFrame(records) with no schema raises "can not infer
    schema from empty dataset" when rows is empty -- which happens whenever
    quintoml's active-prompt manifest has zero active prompts for a run.
    """
    records = []
    for row in rows:
        dt = datetime.strptime(row["day"], DATE_FMT)
        records.append(
            Row(
                prompt_id=row["prompt_id"],
                prompt_hash=row["prompt_hash"],
                inference_status=row["inference_status"],
                year=dt.year,
                month=dt.month,
                day=dt.day,
            )
        )
    return spark.createDataFrame(  # noqa: F821 -- injected by Databricks
        records, schema=INFERENCE_STATUS_SCHEMA
    )


def main() -> None:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod/staging values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source", help="DAG name (vocs_machina_planning)")
    parser.add_argument("table_name")
    parser.add_argument(
        "load_start_date",
        help="This DAG run's ingestion/load date (YYYY-MM-DD), for logging only",
    )
    parser.add_argument(
        "partitions", help="list with partition cols, e.g. \"['year', 'month', 'day']\""
    )
    parser.add_argument(
        "inference_status_rows_json",
        help=(
            "JSON-encoded list of {day, prompt_id, prompt_hash, "
            "inference_status} rows, as published by Task A "
            "(stage_inference_status_to_s3) via XCom"
        ),
    )
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    load_start_date = args.load_start_date
    partition_cols = json.loads(args.partitions.replace("'", '"'))
    rows = json.loads(args.inference_status_rows_json)

    logger.info(
        f"""
        m=main, environment={environment}, source={source}, table_name={table_name},
        load_start_date={load_start_date}, raw_partition_cols={partition_cols},
        msg=Starting Spark job...
        """
    )

    spark_client = SparkClient()
    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW

    spark_metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    )

    logger.info("m=main, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    s3_loader = S3Loader()

    df = build_inference_status_dataframe(rows)

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )
    spark_metastore_loader.update_metastore(
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
        force_recreate=False,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=database_name,
        table_name=table_name,
        df=df,
        partition_cols=partition_cols,
    )


if __name__ == "__main__":
    main()
