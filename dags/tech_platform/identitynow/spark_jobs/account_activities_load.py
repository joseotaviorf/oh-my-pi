import ast
import json
from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import col, dayofmonth, hour, month, to_timestamp, year
from pyspark.sql.types import ArrayType, StructType, StructField, StringType
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import (
    spark
)


JOB_NAME = "identitynow_account_activities_load"
logger = QuintoAndarLogger(JOB_NAME)


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
    args = arg_parser.parse_args()

    args.partition_cols = ast.literal_eval(args.partition_cols)
    args.execution_date = parser.parse(args.execution_date)

    config_service = ConfigurationService(args.source)
    args.input_path = config_service.get_config("input_path")
    args.output_path = config_service.get_config("output_path")

    return args

def load_df(input_path):
    account_activities_schema = StructType([
        StructField("id", StringType(), True),
        StructField("trackingNumber", StringType(), True),
        StructField("type", StringType(), True),
        StructField("sources", StringType(), True),
        StructField("action", StringType(), True),
        StructField("status", StringType(), True),
        StructField("stage", StringType(), True),
        StructField("requester", StructType([
            StructField("id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("type", StringType(), True)
        ]), True),
        StructField("recipient", StructType([
            StructField("id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("type", StringType(), True)
        ]), True),
        StructField("accountRequests", ArrayType(StructType([
            StructField("result", StructType([
                StructField("status", StringType(), True)
            ]), True),
            StructField("accountId", StringType(), True),
            StructField("op", StringType(), True),
            StructField("provisioningTarget", StructType([
                StructField("name", StringType(), True),
                StructField("id", StringType(), True),
                StructField("type", StringType(), True)
            ]), True),
            StructField("source", StructType([
                StructField("name", StringType(), True),
                StructField("id", StringType(), True),
                StructField("type", StringType(), True)
            ]), True),
            StructField("attributeRequests", ArrayType(StructType([
                StructField("op", StringType(), True),
                StructField("name", StringType(), True),
                StructField("value", StringType(), True),
                StructField("result", StructType([
                    StructField("status", StringType(), True)
                ]), True)
            ])), True)
        ])), True),
        StructField("originalRequests", ArrayType(StructType([
            StructField("result", StructType([
                StructField("status", StringType(), True)
            ]), True),
            StructField("accountId", StringType(), True),
            StructField("op", StringType(), True),
            StructField("source", StructType([
                StructField("name", StringType(), True),
                StructField("id", StringType(), True)
            ]), True),
            StructField("attributeRequests", ArrayType(StructType([
                StructField("op", StringType(), True),
                StructField("name", StringType(), True),
                StructField("value", StringType(), True)
            ])), True)
        ])), True),
        StructField("expansionItems", ArrayType(StructType([
            StructField("attributeRequest", StructType([
                StructField("op", StringType(), True),
                StructField("name", StringType(), True),
                StructField("value", StringType(), True)
            ]), True),
            StructField("accountId", StringType(), True),
            StructField("name", StringType(), True),
            StructField("cause", StringType(), True),
            StructField("source", StructType([
                StructField("name", StringType(), True),
                StructField("id", StringType(), True),
                StructField("type", StringType(), True)
            ]), True),
            StructField("id", StringType(), True),
            StructField("state", StringType(), True)
        ])), True),
        StructField("org", StringType(), True),
        StructField("pod", StringType(), True),
        StructField("_type", StringType(), True),
        StructField("_version", StringType(), True),
        StructField("created", StringType(), True),
        StructField("modified", StringType(), True),
        StructField("synced", StringType(), True)
    ])
    return spark.read.format("json").load(input_path, schema=account_activities_schema)

def clean_df(df):
    ts = to_timestamp(col("created"))
    return df.select(
        ts.alias("ts_event"),
        col("id").alias("id_account_activity"),
        col("trackingNumber").alias("tracking_number"),
        col("type"),
        col("sources"),
        col("action"),
        col("status"),
        col("stage"),
        col("requester.id").alias("id_requester"),
        col("requester.name").alias("requester_name"),
        col("requester.type").alias("requester_type"),
        col("recipient.id").alias("id_recipient"),
        col("recipient.name").alias("recipient_name"),
        col("recipient.type").alias("recipient_type"),
        col("accountRequests").alias("account_requests"),
        col("originalrequests").alias("original_requests"),
        col("expansionItems").alias("expansion_items"),
        col("org"),
        col("pod"),
        col("_type"),
        col("_version"),
        col("created"),
        col("modified"),
        col("synced"),
        year(ts).alias("year"),
        month(ts).alias("month"),
        dayofmonth(ts).alias("day"),
        hour(ts).alias("hour")
    ).where(col("created").isNotNull())

def main():
    """
    This DAG loads and cleans IdentityNow account activities.
    """
    args = parse_arguments()
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    logger.info(
        f"""
        m=__main__, environment={args.env}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket}, execution_date={args.execution_date},
        schema={args.schema}, table_name={args.table_name},
        msg=Starting spark job...
        """
    )

    input_path = (
        f"{args.input_path}/raw/"
        f"{args.execution_date.year}/{args.execution_date.month:02}/{args.execution_date.day:02}/*/"
        "account-activities-*.json.gz"
    )
    raw_df = load_df(input_path)
    df = clean_df(raw_df)

    full_clean_table_name = f"datalake_{args.schema}_clean.{args.table_name}"
    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, full_clean_table_name
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(full_clean_table_name)
    loader = DeltaLoader()
    loader.load_table(
        table_name=full_clean_table_name,
        path=f"{args.output_path}/clean/{args.schema}/{args.table_name}/",
        source_df=df,
        partition_by=args.partition_cols
    )
    if (
        table_privileges
        and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
    ):
        table_privileges.apply()


if __name__ == "__main__":
    main()
