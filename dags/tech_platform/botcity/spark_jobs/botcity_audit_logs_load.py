import ast
from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import col, dayofmonth, hour, month, to_timestamp, year
from pyspark.sql import DataFrame
from pyspark.sql.types import StructType, StructField, StringType
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import (
    spark
)


JOB_NAME = "botcity_audit_logs_load"
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

    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partition_cols)
    args.execution_date = parser.parse(args.execution_date)

    config_service = ConfigurationService(args.source)
    args.path = config_service.get_config("path")

    return args


def clean_df(data_frame: 'DataFrame') -> 'DataFrame':
    """
    Transform json to struct data and extract only the necessary columns.
    Deduplicate rows based on id_event (log_id).
    """
    ts = to_timestamp(col("date"))

    data_frame = data_frame.select(
        ts.alias("ts_event"),
        col("log_id").alias("id_event"),
        col("user.email").alias("user_email"),
        col("user.name").alias("user_name"),
        col("source").alias("source"),
        col("type").alias("type"),
        col("organization").alias("organization"),
        col("params.resource").alias("params_resource"),
        col("params.name").alias("params_name"),
        col("params.id").alias("id_params"),
        col("params.automation").alias("params_automation"),
        col("params.cron").alias("params_cron"),
        col("params.version").alias("params_version"),
        col("params.releaseVersion").alias("params_release"),
        year(ts).alias("year"),
        month(ts).alias("month"),
        dayofmonth(ts).alias("day"),
        hour(ts).alias("hour")
    )

    data_frame = data_frame.dropDuplicates(["id_event"])

    return data_frame


def load_data_frame(path):
    botcity_audit_logs_schema = StructType([
        StructField("user", StructType([
            StructField("email", StringType(), True),
            StructField("name", StringType(), True)
        ]), True),
        StructField("log_id", StringType(), True),
        StructField("source", StringType(), True),
        StructField("type", StringType(), True),
        StructField("organization", StringType(), True),
        StructField("date", StringType(), True),
        StructField("params", StructType([
            StructField("resource", StringType(), True),
            StructField("name", StringType(), True),
            StructField("id", StringType(), True),
            StructField("automation", StringType(), True),
            StructField("cron", StringType(), True),
            StructField("version", StringType(), True),
            StructField("releaseVersion", StringType(), True)
        ]), True)
    ])

    return spark.read.format('json').load(path, schema=botcity_audit_logs_schema)


def main():
    """
    This DAG loads and cleans BotCity audit logs.
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

    audit_logs_path = args.path.format(
        f'year={args.execution_date.year}',
        f'month={args.execution_date.month:02}',
        f'day={args.execution_date.day:02}',
    )
    raw_data_frame = load_data_frame(audit_logs_path)
    clean_data_frame = clean_df(raw_data_frame)

    DeltaLoader().load_table(
        table_name=f"datalake_{args.schema}_clean.{args.table_name}",
        path=f"s3://{args.datalake_bucket}/clean/{args.schema}/{args.table_name}/",
        source_df=clean_data_frame,
        partition_by=args.partition_cols,
        merge_on=["id_event"]
    )


if __name__ == "__main__":
    main()
