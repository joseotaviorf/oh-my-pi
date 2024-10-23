import ast
from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import col, to_timestamp, concat, to_timestamp, year, month, dayofmonth, hour, lit
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import (
    spark
)

JOB_NAME = "cloudfront_logs_load"
logger = QuintoAndarLogger(JOB_NAME)


def clean_cf(df):
    """
    Transform extract only the necessary columns.
    """

    ts = to_timestamp(concat(col("date"), lit(" "), col("time")))
    df = df.select(ts.alias("ts_event"), 
                col("time-taken").alias("request_duration_s"),
                col("x-edge-location").alias("edge_location"),
                col("c_ip").alias("principal_ip"),
                col("c_port").alias("principal_port"),
                col("cs_method").alias("request_method"),
                col("cs(Host)").alias("request_host"),
                col("cs-uri-stem").alias("request_path"),
                col("cs(User-Agent)").alias("request_user_agent"),
                col("cs-uri-query").alias("request_query"),
                col("sc-status").alias("response_code"),
                col("x-edge-result-type").alias("request_result_type"),
                col("x-edge-request-id").alias("id_request"),
                year(ts).alias("year"),
                month(ts).alias("month"),
                dayofmonth(ts).alias("day"),
                hour(ts).alias("hour")                
              ).where(col("date").isNotNull())

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
    This DAG loads and cleans Cloudfront logs.
    In this case we loading and cleaning the data directly from the source.
    Reason is that we have high volume of data, with fairly immutable schema,
    thus we are optimizing for less stages due to cost.
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

    schema = [
        "date", "time", "x_edge_location", "sc_bytes", "c_ip", "cs_method", "cs_host",
        "cs_uri_stem", "sc_status", "cs_referer", "cs_user_agent", "cs_uri_query",
        "cs_cookie", "x_edge_result_type", "x_edge_request_id", "x_host_header",
        "cs_protocol", "cs_bytes", "time_taken", "x_forwarded_for", "ssl_protocol",
        "ssl_cipher", "x_edge_response_result_type", "cs_protocol_version", "fle_status",
        "fle_encrypted_fields", "c_port", "time_to_first_byte", "x_edge_detailed_result_type",
        "sc_content_type", "sc_content_len", "sc_range_start", "sc_range_end"
    ]

    df = spark.read.format("csv")\
        .option("sep", "\t").option("comment", "#")\
        .option("nullValue", "-")\
        .load(args.path.format(
                args.execution_date.year,
                str(args.execution_date.month).zfill(2),
                str(args.execution_date.day).zfill(2),
                str(args.execution_date.hour).zfill(2)
        )).toDF(*schema)
    df = clean_cf(df)

    DeltaLoader().load_table(
        table_name=f"datalake_{args.schema}_clean.{args.table_name}",
        path=f"s3://{args.datalake_bucket}/clean/{args.schema}/{args.table_name}/",
        source_df=df,
        partition_by=args.partition_cols,
    )

if __name__ == "__main__":
    main()