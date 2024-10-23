import ast
from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import split, when, element_at, lit, col, from_json, year, month, dayofmonth, hour, to_timestamp
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import (
    spark
)


JOB_NAME = "opa_logs_load"
logger = QuintoAndarLogger(JOB_NAME)


def clean_cf(df):
    """
    Transform json to struct data and extract only the necessary columns.
    """
    dynamic_schema = spark.read.json(df.rdd.map(lambda row: row.message)).schema
    df = df.withColumn("data", from_json(col("message"), dynamic_schema))
    ts = to_timestamp(col("data.timestamp"))
    traceparent = col("data.input.attributes.request.http.headers.traceparent")

    trace_id = when(
        traceparent.isNotNull() & 
        traceparent.contains("-"),
        element_at(split(traceparent, "-"), 2)
    ).otherwise(lit(None))

    df = df.select(
        ts.alias("ts_event"), 
        trace_id.alias("id_trace"),
        traceparent.alias("request_traceparent"), 
        col("data.bundles").alias("bundles"), 
        col("data.decision_id").alias("id_decision"), 
        "data.erased", 
        col("data.input.attributes.source.principal").alias("request_source_principal"), 
        col("data.input.attributes.destination.principal").alias("request_destination_principal"), 
        col("data.input.attributes.request.http.headers.x-request-id").alias("id_request"), 
        col("data.input.attributes.request.http.headers.x-amz-cf-id").alias("id_amz_cf"), 
        col("data.result.dynamic_metadata.parameterized_path").alias("request_path"), 
        col("data.result.principalinfo.authorized_by").alias("request_authorized_by"), 
        col("data.result.principalinfo.required_roles").alias("request_required_roles"), 
        col("data.result.allowed").alias("result_http_allowed"), 
        col("data.result.http_status").alias("result_http_status"), 
        col("data.result.principalinfo.user.payload.email").alias("principal_user_email"), 
        col("data.result.principalinfo.user.provided_roles").alias("principal_user_provided_roles"), 
        col("data.result.principalinfo.user.payload.providerId").alias("principal_user_idp"), 
        col("data.result.principalinfo.service.provided_roles").alias("principal_service_provided_roles"), 
        col("data.result.principalinfo.service.id").alias("principal_service"),
        col("app"),
        year(ts).alias("year"),
        month(ts).alias("month"),
        dayofmonth(ts).alias("day"),
        hour(ts).alias("hour")
            ).where(col("data.timestamp").isNotNull())
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
    This DAG loads and cleans OPA logs.
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


if __name__ == "__main__":
    main()