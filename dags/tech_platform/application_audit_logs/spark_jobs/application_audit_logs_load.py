import ast
import json
from argparse import ArgumentParser

from dateutil import parser
from pyspark.sql.functions import col, from_json, get_json_object, to_timestamp
from pyspark.sql.types import StringType, StructField, StructType
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import spark
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.base.validation.target_resolver import managed_table_fqn
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "application_audit_logs_load"
logger = QuintoAndarLogger(JOB_NAME)
_CLEAN_LAYER = LayerEnum.CLEAN.value


def clean_cf(df):
    """
    Transform json to struct data and extract only the necessary columns.
    Parse the message field which contains audit log JSON with trace_id, payload, etc.
    The payload is stored as a JSON string to support any structure (nested objects, arrays).
    """
    # Parse the message field as JSON
    df = df.withColumn(
        "data", from_json(col("message"), get_application_audit_logs_schema())
    )

    # Use the timestamp from the message data
    ts_event = to_timestamp(col("data.timestamp"))

    df = df.select(
        ts_event.alias("ts_event"),
        col("data.trace_id").alias("id_trace"),
        col("data.id").alias("id_log"),
        get_json_object(col("data.payload"), "$.transaction_id").alias(
            "id_transaction"
        ),
        col("data.payload").alias("payload"),
        col("app"),
        col("namespace"),
        col("pod_name"),
        col("log_year").alias("year"),
        col("log_month").alias("month"),
        col("log_day").alias("day"),
        col("log_hour").alias("hour"),
    ).where(col("data.timestamp").isNotNull())

    return df


def get_table_privileges(args):
    """
    Get table privileges for the application audit logs table.
    """
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
    else:
        return TablePrivileges.from_environment_default(full_table_name)


def parse_arguments():
    arg_parser = ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("source")
    arg_parser.add_argument("env")
    arg_parser.add_argument("datalake_bucket")
    arg_parser.add_argument("schema")
    arg_parser.add_argument("execution_date")
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
    add_validation_target_args(arg_parser)

    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partition_cols)
    args.execution_date = parser.parse(args.execution_date)

    config_service = ConfigurationService(args.source)
    args.path = config_service.get_config("path")

    return args


def main():
    """
    This DAG loads and cleans application audit logs.
    These logs come from various applications (login, person-api, etc.) and contain
    audit events with trace_id, payload data, and metadata.
    """
    args = parse_arguments()
    logger.info(
        f"""
        m=__main__, environment={args.env}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket}, execution_date={args.execution_date},
        schema={args.schema}, table_name={args.table_name},
        msg=Starting spark job...
        """
    )

    df = spark.read.format("json").load(
        args.path.format(
            args.execution_date.year,
            str(args.execution_date.month).zfill(2),
            str(args.execution_date.day).zfill(2),
            str(args.execution_date.hour).zfill(2),
        )
    )
    df = clean_cf(df)

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
    )

    table_privileges = get_table_privileges(args)

    if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        table_privileges.apply()


def get_application_audit_logs_schema():
    """
    Schema for application audit logs.
    The payload field is kept as a raw string to handle any JSON structure (nested objects, arrays, etc).
    It will be stored as a JSON string that can be queried using get_json_object() or from_json().
    """
    return StructType(
        [
            StructField("trace_id", StringType(), True),
            StructField("id", StringType(), True),
            StructField("timestamp", StringType(), True),
            StructField("payload", StringType(), True),
        ]
    )


if __name__ == "__main__":
    main()
