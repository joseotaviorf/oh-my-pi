import ast
from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import split, when, element_at, lit, col, from_json, year, month, dayofmonth, hour, to_timestamp
from pyspark.sql.types import StructType, StructField, StringType, ArrayType, LongType, DoubleType, BooleanType
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
    # Make sure we handle escaped quotes
    message = translate(col("message"), '\\"', '"')
    df = df.withColumn("data", from_json(message, get_opa_schema()))
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
        col("data.result.dynamic_metadata.parameterized_path").alias("request_parameterized_path"),
        col("data.input.attributes.request.http.method").alias("request_method"),
        col("data.input.attributes.request.http.path").alias("request_path"), 
        col("data.result.principalinfo.authorized_by").alias("request_authorized_by"), 
        col("data.result.principalinfo.required_roles").alias("request_required_roles"), 
        col("data.result.allowed").alias("result_http_allowed"), 
        col("data.result.http_status").alias("result_http_status"), 
        col("data.result.principalinfo.user.payload.email").alias("principal_user_email"), 
        col("data.result.principalinfo.user.provided_roles").alias("principal_user_provided_roles"), 
        col("data.result.principalinfo.user.payload.providerId").alias("principal_user_idp"), 
        col("data.result.principalinfo.user.payload.iss").alias("principal_user_issuer"), 
        col("data.result.principalinfo.user.payload.sudoed_by_id").alias("id_principal_user_impersonated_by"), 
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


def get_opa_schema():
    return StructType([
        StructField('bundles', StructType([
            StructField('app', StructType([
                StructField('revision', StringType(), True)
            ]), True),
            StructField('data', StructType([
                StructField('revision', StringType(), True)
            ]), True),
            StructField('idm', StructType([
                StructField('revision', StringType(), True)
            ]), True)
        ]), True),
        StructField('client_addr', StringType(), True),
        StructField('current_version', StringType(), True),
        StructField('decision_id', StringType(), True),
        StructField('download_opa', StringType(), True),
        StructField('erased', ArrayType(StringType(), True), True),
        StructField('error', StructType([
            StructField('code', StringType(), True),
            StructField('message', StringType(), True)
        ]), True),
        StructField('file', StringType(), True),
        StructField('input', StructType([
            StructField('attributes', StructType([
                StructField('destination', StructType([
                    StructField('address', StructType([
                        StructField('socketAddress', StructType([
                            StructField('address', StringType(), True),
                            StructField('portValue', LongType(), True)
                        ]), True)
                    ]), True),
                    StructField('principal', StringType(), True)
                ]), True),
                StructField('request', StructType([
                    StructField('http', StructType([
                        StructField('headers', StructType([
                            StructField(':authority', StringType(), True),
                            StructField(':method', StringType(), True),
                            StructField(':path', StringType(), True),
                            StructField(':scheme', StringType(), True),
                            StructField('accept', StringType(), True),
                            StructField('accept-charset', StringType(), True),
                            StructField('accept-encoding', StringType(), True),
                            StructField('accept-language', StringType(), True),
                            StructField('alt-used', StringType(), True),
                            StructField('apikey-cdn', StringType(), True),
                            StructField('authority', StringType(), True),
                            StructField('b3', StringType(), True),
                            StructField('baggage', StringType(), True),
                            StructField('cloudfront-forwarded-proto', StringType(), True),
                            StructField('cloudfront-is-desktop-viewer', StringType(), True),
                            StructField('cloudfront-is-mobile-viewer', StringType(), True),
                            StructField('cloudfront-is-smarttv-viewer', StringType(), True),
                            StructField('cloudfront-is-tablet-viewer', StringType(), True),
                            StructField('cloudfront-viewer-asn', StringType(), True),
                            StructField('cloudfront-viewer-country', StringType(), True),
                            StructField('content-length', StringType(), True),
                            StructField('content-type', StringType(), True),
                            StructField('dnt', StringType(), True),
                            StructField('origin', StringType(), True),
                            StructField('priority', StringType(), True),
                            StructField('purpose', StringType(), True),
                            StructField('referer', StringType(), True),
                            StructField('save-data', StringType(), True),
                            StructField('sec-ch-ua', StringType(), True),
                            StructField('sec-ch-ua-mobile', StringType(), True),
                            StructField('sec-ch-ua-platform', StringType(), True),
                            StructField('sec-fetch-dest', StringType(), True),
                            StructField('sec-fetch-mode', StringType(), True),
                            StructField('sec-fetch-site', StringType(), True),
                            StructField('sec-gpc', StringType(), True),
                            StructField('sec-purpose', StringType(), True),
                            StructField('sentry-trace', StringType(), True),
                            StructField('traceparent', StringType(), True),
                            StructField('tracestate', StringType(), True),
                            StructField('user-agent', StringType(), True),
                            StructField('via', StringType(), True),
                            StructField('x-amz-cf-id', StringType(), True),
                            StructField('x-amzn-trace-id', StringType(), True),
                            StructField('x-b3-parentspanid', StringType(), True),
                            StructField('x-b3-sampled', StringType(), True),
                            StructField('x-b3-spanid', StringType(), True),
                            StructField('x-b3-traceid', StringType(), True),
                            StructField('x-consumer-id', StringType(), True),
                            StructField('x-consumer-username', StringType(), True),
                            StructField('x-country-code', StringType(), True),
                            StructField('x-credential-identifier', StringType(), True),
                            StructField('x-envoy-attempt-count', StringType(), True),
                            StructField('x-envoy-internal', StringType(), True),
                            StructField('x-forwarded-client-cert', StringType(), True),
                            StructField('x-forwarded-for', StringType(), True),
                            StructField('x-forwarded-host', StringType(), True),
                            StructField('x-forwarded-path', StringType(), True),
                            StructField('x-forwarded-port', StringType(), True),
                            StructField('x-forwarded-proto', StringType(), True),
                            StructField('x-instana-l', StringType(), True),
                            StructField('x-instana-s', StringType(), True),
                            StructField('x-instana-t', StringType(), True),
                            StructField('x-kong-token', StringType(), True),
                            StructField('x-original-requester', StringType(), True),
                            StructField('x-prometheus-scrape-timeout-seconds', StringType(), True),
                            StructField('x-real-ip', StringType(), True),
                            StructField('x-request-id', StringType(), True),
                            StructField('x-requested-with', StringType(), True),
                            StructField('x-trace-data', StringType(), True)
                        ]), True),
                        StructField('host', StringType(), True),
                        StructField('id', StringType(), True),
                        StructField('method', StringType(), True),
                        StructField('path', StringType(), True),
                        StructField('protocol', StringType(), True),
                        StructField('scheme', StringType(), True)
                    ]), True),
                    StructField('time', StringType(), True)
                ]), True),
                StructField('source', StructType([
                    StructField('address', StructType([
                        StructField('socketAddress', StructType([
                            StructField('address', StringType(), True),
                            StructField('portValue', LongType(), True)
                        ]), True)
                    ]), True),
                    StructField('principal', StringType(), True)
                ]), True)
            ]), True)
        ]), True),
        StructField('parsed_path', ArrayType(StringType(), True), True),
        StructField('version', StructType([
            StructField('encoding', StringType(), True),
            StructField('ext_authz', StringType(), True)
        ]), True),
        StructField('labels', StructType([
            StructField('app_name', StringType(), True),
            StructField('app_revision', StringType(), True),
            StructField('env', StringType(), True),
            StructField('id', StringType(), True),
            StructField('version', StringType(), True)
        ]), True),
        StructField('latest_version', StringType(), True),
        StructField('level', StringType(), True),
        StructField('metrics', StructType([
            StructField('timer_rego_external_resolve_ns', LongType(), True),
            StructField('timer_rego_query_eval_ns', LongType(), True),
            StructField('timer_server_handler_ns', LongType(), True)
        ]), True),
        StructField('msg', StringType(), True),
        StructField('path', StringType(), True),
        StructField('plugin', StringType(), True),
        StructField('release_notes', StringType(), True),
        StructField('req_id', LongType(), True),
        StructField('req_method', StringType(), True),
        StructField('req_path', StringType(), True),
        StructField('resp_bytes', LongType(), True),
        StructField('resp_duration', DoubleType(), True),
        StructField('resp_status', LongType(), True),
        StructField('result', StructType([
            StructField('allowed', BooleanType(), True),
            StructField('dynamic_metadata', StructType([
                StructField('parameterized_path', StringType(), True)
            ]), True),
            StructField('error', StringType(), True),
            StructField('http_status', LongType(), True),
            StructField('principalinfo', StructType([
                StructField('authorized_by', StringType(), True),
                StructField('required_roles', ArrayType(StringType(), True), True),
                StructField('service', StructType([
                    StructField('id', StringType(), True),
                    StructField('provided_roles', ArrayType(StringType(), True), True)
                ]), True),
                StructField('user', StructType([
                    StructField('payload', StructType([
                        StructField('agent_id', LongType(), True),
                        StructField('aud', ArrayType(StringType(), True), True),
                        StructField('auth_time', LongType(), True),
                        StructField('azp', StringType(), True),
                        StructField('clientAddress', StringType(), True),
                        StructField('clientHost', StringType(), True),
                        StructField('clientId', StringType(), True),
                        StructField('created_timestamp', StringType(), True),
                        StructField('creationDate', StringType(), True),
                        StructField('email', StringType(), True),
                        StructField('email_verified', BooleanType(), True),
                        StructField('exp', LongType(), True),
                        StructField('family_name', StringType(), True),
                        StructField('firstname', StringType(), True),
                        StructField('given_name', StringType(), True),
                        StructField('iat', LongType(), True),
                        StructField('id', LongType(), True),
                        StructField('iss', StringType(), True),
                        StructField('jti', StringType(), True),
                        StructField('kubernetes.io', StructType([
                            StructField('namespace', StringType(), True),
                            StructField('pod', StructType([
                                StructField('name', StringType(), True),
                                StructField('uid', StringType(), True)
                            ]), True),
                            StructField('serviceaccount', StructType([
                                StructField('name', StringType(), True),
                                StructField('uid', StringType(), True)
                            ]), True)
                        ]), True),
                        StructField('main_user_id', StringType(), True),
                        StructField('name', StringType(), True),
                        StructField('nbf', LongType(), True),
                        StructField('nonce', StringType(), True),
                        StructField('partner_id', LongType(), True),
                        StructField('personUUID', StringType(), True),
                        StructField('preferred_username', StringType(), True),
                        StructField('providerId', StringType(), True),
                        StructField('roles', StringType(), True),
                        StructField('scope', StringType(), True),
                        StructField('session_state', StringType(), True),
                        StructField('sid', StringType(), True),
                        StructField('sub', StringType(), True),
                        StructField('sudoed_by_id', LongType(), True),
                        StructField('telefone', StringType(), True),
                        StructField('titulo', StringType(), True),
                        StructField('typ', StringType(), True),
                        StructField('userCreatedAt', StringType(), True),
                        StructField('userId', StringType(), True)
                    ]), True),
                    StructField('provided_roles', ArrayType(StringType(), True), True)
                ]), True)
            ]), True),
            StructField('request_headers_to_remove', ArrayType(StringType(), True), True)
        ]), True),
        StructField('span_id', StringType(), True),
        StructField('time', StringType(), True),
        StructField('timestamp', StringType(), True),
        StructField('trace_id', StringType(), True),
        StructField('type', StringType(), True)
])

if __name__ == "__main__":
    main()