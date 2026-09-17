"""Clean EMR EventBridge envelopes from Firehose → datalake_emr_events_clean.events.

Reads gzipped newline-delimited JSON under day prefixes:
s3://artifacts.s3.data.quintoandar.com.br/emr/events/{yyyy}/{MM}/{dd}/*.
Grain: one row per envelope `id`. Runs over a date window [load_start_date, load_end_date)
(end date exclusive). Missing day prefixes yield an empty DataFrame instead of failing.
"""

from __future__ import annotations

import ast
import json
from argparse import ArgumentParser
from datetime import date, timedelta

import yaml
from pyspark.sql.functions import (
    col,
    current_timestamp,
    dayofmonth,
    get_json_object,
    hour,
    lpad,
    month,
    to_json,
    to_timestamp,
    when,
    year,
)
from pyspark.sql.types import StringType, StructField, StructType, TimestampType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import spark
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.base.validation.target_resolver import managed_table_fqn
from bietlejuice.loaders.delta_loader import DeltaLoader

JOB_NAME = "load_emr_events"
logger = QuintoAndarLogger(JOB_NAME)
_CLEAN_LAYER = LayerEnum.CLEAN.value

_STEP_DETAIL_TYPE = "EMR Step Status Change"

OUTPUT_SCHEMA = StructType(
    [
        StructField("id_event", StringType(), False),
        StructField("id_emr_cluster", StringType(), True),
        StructField("id_emr_step", StringType(), True),
        StructField("detail_type", StringType(), True),
        StructField("event_state", StringType(), True),
        StructField("state_change_reason", StringType(), True),
        StructField("severity", StringType(), True),
        StructField("cluster_name", StringType(), True),
        StructField("step_name", StringType(), True),
        StructField("message", StringType(), True),
        StructField("id_aws_account", StringType(), True),
        StructField("ts_event", TimestampType(), True),
        StructField("ts_load", TimestampType(), True),
        StructField("year", StringType(), True),
        StructField("month", StringType(), True),
        StructField("day", StringType(), True),
        StructField("hour", StringType(), True),
    ]
)


def _empty_df():
    return spark.createDataFrame([], schema=OUTPUT_SCHEMA)


def clean_events(df):
    """Project the EventBridge envelope into typed columns.

    `detail.name` is the cluster name on cluster events and the step name on
    step events — split by `detail-type`, never mapped to one column.
    `stateChangeReason` may be a string or an object; store the JSON text.
    """
    detail_json = to_json(col("detail"))
    ts_event = to_timestamp(col("time"))
    detail_type = col("`detail-type`")
    detail_name = get_json_object(detail_json, "$.name")

    return df.select(
        col("id").alias("id_event"),
        get_json_object(detail_json, "$.clusterId").alias("id_emr_cluster"),
        get_json_object(detail_json, "$.stepId").alias("id_emr_step"),
        detail_type.alias("detail_type"),
        get_json_object(detail_json, "$.state").alias("event_state"),
        get_json_object(detail_json, "$.stateChangeReason").alias(
            "state_change_reason"
        ),
        get_json_object(detail_json, "$.severity").alias("severity"),
        when(detail_type != _STEP_DETAIL_TYPE, detail_name).alias("cluster_name"),
        when(detail_type == _STEP_DETAIL_TYPE, detail_name).alias("step_name"),
        get_json_object(detail_json, "$.message").alias("message"),
        col("account").alias("id_aws_account"),
        ts_event.alias("ts_event"),
        current_timestamp().alias("ts_load"),
        year(ts_event).cast("string").alias("year"),
        lpad(month(ts_event).cast("string"), 2, "0").alias("month"),
        lpad(dayofmonth(ts_event).cast("string"), 2, "0").alias("day"),
        lpad(hour(ts_event).cast("string"), 2, "0").alias("hour"),
    ).where(col("id").isNotNull())


def get_table_privileges(args):
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    prod_database = f"datalake_{args.schema}_clean"
    full_table_name = managed_table_fqn(
        prod_database=prod_database,
        prod_table=args.table_name,
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    if table_privileges_dict is not None:
        return TablePrivileges.from_input_dict(table_privileges_dict, full_table_name)
    return TablePrivileges.from_environment_default(full_table_name)


def parse_arguments():
    arg_parser = ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("source")
    arg_parser.add_argument("env")
    arg_parser.add_argument("datalake_bucket")
    arg_parser.add_argument("schema")
    arg_parser.add_argument("load_start_date")
    arg_parser.add_argument("load_end_date")
    arg_parser.add_argument("table_name")
    arg_parser.add_argument("partition_cols")
    arg_parser.add_argument(
        "-tp",
        "--table-privileges",
        type=lambda arg: None if not arg else arg,
        help="json string mapping each principal to a list of permissions for the table",
        required=False,
        default=None,
    )
    arg_parser.add_argument(
        "--merge-on",
        type=lambda arg: None if not arg else arg,
        help="json list of columns used as MERGE keys",
        required=False,
        default=None,
    )
    add_validation_target_args(arg_parser)

    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partition_cols)
    args.merge_on = json.loads(args.merge_on) if args.merge_on else None
    args.load_start_date = date.fromisoformat(args.load_start_date)
    args.load_end_date = date.fromisoformat(args.load_end_date)

    environment_conf = yaml.safe_load(
        DAGPackagesPathService.get_config_file_content_in_spark_jobs(
            args.source, f"{args.env}_conf.yml"
        )
    )
    args.path = environment_conf["path"]
    return args


def build_day_paths(
    load_start_date: date, load_end_date: date, path_template: str
) -> list[str]:
    paths = []
    current = load_start_date
    while current < load_end_date:
        paths.append(
            path_template.format(
                current.year,
                str(current.month).zfill(2),
                str(current.day).zfill(2),
            )
        )
        current += timedelta(days=1)
    return paths


def filter_existing_day_paths(spark_session, day_paths: list[str]) -> list[str]:
    hadoop_configuration = spark_session.sparkContext._jsc.hadoopConfiguration()
    existing_paths = []
    for day_path in day_paths:
        day_prefix = spark_session._jvm.org.apache.hadoop.fs.Path(day_path.rstrip("*"))
        if day_prefix.getFileSystem(hadoop_configuration).exists(day_prefix):
            existing_paths.append(day_path)
    return existing_paths


def main():
    args = parse_arguments()
    logger.info(
        f"""
        m=__main__, environment={args.env}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket},
        load_start_date={args.load_start_date}, load_end_date={args.load_end_date},
        schema={args.schema}, table_name={args.table_name},
        msg=Starting spark job...
        """
    )

    day_paths = build_day_paths(args.load_start_date, args.load_end_date, args.path)
    existing_paths = filter_existing_day_paths(spark, day_paths)
    logger.info(
        f"m=main, load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, "
        f"day_paths={len(day_paths)}, existing_day_paths={len(existing_paths)}"
    )

    if existing_paths:
        df = clean_events(spark.read.format("json").load(existing_paths))
    else:
        logger.warning(
            "m=main, msg=No EMR event day prefixes exist for the window, writing empty frame"
        )
        df = _empty_df()

    if args.merge_on:
        # Firehose delivery is at-least-once, so one day prefix can carry the
        # same envelope twice. A duplicated merge key aborts the MERGE with
        # "multiple source rows matched a target row".
        df = df.dropDuplicates(args.merge_on)

    database_name, database_location, _ = DatalakeMetastoreService.get_layer_info(
        args.env, args.schema, args.datalake_bucket, _CLEAN_LAYER
    )
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=args.table_name,
            prod_location=database_location,
            bucket=args.datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    DeltaLoader().load_table(
        table_name=f"{write_database_name}.{write_table_name}",
        path=f"{write_location.rstrip('/')}/{write_table_name}",
        source_df=df,
        partition_by=args.partition_cols,
        merge_on=args.merge_on,
    )

    table_privileges = get_table_privileges(args)
    if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        table_privileges.apply()


if __name__ == "__main__":
    main()
