import ast
from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import split, when, lit, element_at, col, year, month, dayofmonth, hour, to_timestamp, from_json
from pyspark.sql.types import StructType, StructField, StringType, LongType
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import (
    spark
)


JOB_NAME = "istio_logs_load"
logger = QuintoAndarLogger(JOB_NAME)


def clean_cf(df):
    """
    Transform extract only the necessary columns.
    """

    df = df.withColumn("data", from_json(col("message"), get_istio_schema()))
    ts = to_timestamp(col("timestamp"))
    ts_event = to_timestamp(col("data.start_time"))
    traceparent = col("data.traceparent")

    trace_id = when(
        traceparent.isNotNull() &
        traceparent.contains("-"),
        element_at(split(traceparent, "-"), 2)
    ).otherwise(lit(None))

    df = df.select(
               ts_event.alias("ts_event"),
               trace_id.alias("id_trace"),
               traceparent.alias("request_traceparent"),
               col("namespace"),
               col("pod_name"),
               col("data.method").alias("request_method"),
               col("data.user_agent").alias("request_user_agent"),
               col("data.path").alias("request_path"),
               col("data.duration").alias("request_duration_ms"),
               col("data.x_forwarded_for").alias("request_x_forwarded_for"),
               col("data.response_flags").alias("response_flags"),
               col("data.response_code").alias("response_code"),
               col("data.request_id").alias("id_request"),
               col("app"),
               year(ts).alias("year"),
               month(ts).alias("month"),
               dayofmonth(ts).alias("day"),
               hour(ts).alias("hour")
              ).where(col("data.start_time").isNotNull())

    return df


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

def main():
    """
    This DAG loads and cleans Istio logs.
    In this case we loading and cleaning the data directly from the source.
    Reason is that we have high volume of data, with fairly immutable schema,
    thus we are optimizing for less stages due to cost.
    """
    args = parse_arguments()
    logger.info(
        f"""
        m=__main__, environment={args.env}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket}, execution_date={args.execution_date},
        schema={args.schema}, table_name={args.table_name}, partition_cols={args.partition_cols},
        msg=Starting spark job...
        """
    )

    df = spark.read.format("json").load(args.path.format(
                args.execution_date.year,
                str(args.execution_date.month).zfill(2),
                str(args.execution_date.day).zfill(2),
                str(args.execution_date.hour).zfill(2)
    ))
    df = clean_cf(df)

    DeltaLoader().load_table(
        table_name=f"datalake_{args.schema}_clean.{args.table_name}",
        path=f"s3://{args.datalake_bucket}/clean/{args.schema}/{args.table_name}/",
        source_df=df,
        partition_by=args.partition_cols,
    )

def get_istio_schema():
    return StructType([
        StructField('response_code', LongType(), True),
        StructField('upstream_service_time', StringType(), True),
        StructField('method', StringType(), True),
        StructField('traceparent', StringType(), True),
        StructField('downstream_remote_address', StringType(), True),
        StructField('upstream_local_address', StringType(), True),
        StructField('bytes_sent', LongType(), True),
        StructField('user_agent', StringType(), True),
        StructField('x_forwarded_for', StringType(), True),
        StructField('path', StringType(), True),
        StructField('upstream_host', StringType(), True),
        StructField('requested_server_name', StringType(), True),
        StructField('request_id', StringType(), True),
        StructField('protocol', StringType(), True),
        StructField('route_name', StringType(), True),
        StructField('upstream_transport_failure_reason', StringType(), True),
        StructField('downstream_local_address', StringType(), True),
        StructField('bytes_received', LongType(), True),
        StructField('start_time', StringType(), True),
        StructField('response_flags', StringType(), True),
        StructField('upstream_cluster', StringType(), True),
        StructField('authority', StringType(), True),
        StructField('istio_policy_status', StringType(), True),
        StructField('duration', LongType(), True)
    ])

if __name__ == "__main__":
    main()
