import ast
from argparse import ArgumentParser
from dateutil import parser

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.loaders.delta_loader import DeltaLoader
from pyspark.sql.functions import (
    coalesce,
    col,
    dayofmonth,
    element_at,
    from_json,
    get_json_object,
    hour,
    lit,
    map_values,
    month,
    regexp_replace,
    split,
    to_timestamp,
    when,
    year,
)
from pyspark.sql.types import (
    LongType,
    MapType,
    StringType,
    StructField,
    StructType,
)
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import (
    spark
)


JOB_NAME = "istio_logs_load"
logger = QuintoAndarLogger(JOB_NAME)


# Outer envelope of each Istio log file. Only the fields actually consumed
# downstream are declared; extra fields in the source JSON are ignored by
# the reader. Providing an explicit schema avoids Spark's schema-inference
# pass, which otherwise re-lists and re-reads every file under the path.
OUTER_SCHEMA = StructType([
    StructField("timestamp", StringType(), True),
    StructField("message", StringType(), True),
    StructField("namespace", StringType(), True),
    StructField("pod_name", StringType(), True),
    StructField("app", StringType(), True),
])


def _extract_principal_identities_json():
    """
    Extract the identities JSON object from the JWT user payload, handling both formats:
      - Forno/Staging:  result.principal_info.user = {email, identities, ...}  (flat)
      - Production:     result.principal_info.user = {<issuer>: {email, identities, ...}}  (wrapped)

    get_json_object is used instead of schema-based parsing because `identities` is a nested
    JSON object; from_json with StringType returns null for object-typed values.
    """
    user_raw = col("data.result.principal_info.user")
    user_map = from_json(user_raw, MapType(StringType(), StringType()))
    wrapped_inner_json = element_at(map_values(user_map), 1)
    return coalesce(
        get_json_object(wrapped_inner_json, "$.identities"),
        get_json_object(user_raw, "$.identities"),
    )


def _extract_principal_service():
    """
    Extract and normalise the mTLS service identity from the SPIFFE URI, filtering out
    noise services irrelevant to audit purposes.
    """
    _noise_services = ["default", "kong-serviceaccount", "kong-private-controller", "kong-public-controller"]
    service = regexp_replace(
        col("data.result.principal_info.service"),
        r"^spiffe://cluster\.local/ns/[^/]+/sa/",
        "",
    )
    
    return when(service.isin(_noise_services), lit(None)).otherwise(service)


def _parse_user_claims(df):
    """
    Parse JWT claims from the user field, handling both formats:
      - Forno/Staging:  result.principal_info.user = {email, id, ...}
      - Production:     result.principal_info.user = {<issuer>: {email, id, ...}}
    """
    claims_schema = get_claims_schema()
    user_raw = col("data.result.principal_info.user")

    direct = from_json(user_raw, claims_schema)
    user_map = from_json(user_raw, MapType(StringType(), StringType()))
    wrapped = from_json(element_at(map_values(user_map), 1), claims_schema)

    return df.withColumn("direct", direct).withColumn("wrapped", wrapped)


def clean_cf(df):
    """
    Transform extract only the necessary columns.
    """

    df = df.withColumn("data", from_json(col("message"), get_istio_schema()))
    df = _parse_user_claims(df)

    ts = to_timestamp(col("timestamp"))
    ts_event = to_timestamp(col("data.start_time"))
    traceparent = col("data.traceparent")

    trace_id = when(
        traceparent.isNotNull() &
        traceparent.contains("-"),
        element_at(split(traceparent, "-"), 2)
    ).otherwise(lit(None))

    principal_identities_json = _extract_principal_identities_json()
    principal_service = _extract_principal_service()

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
               coalesce(col("direct.personUUID"), col("wrapped.personUUID")).alias("uuid_person_principal_user"),
               coalesce(col("direct.id"), col("wrapped.id")).alias("id_principal_user"),
               coalesce(col("direct.email"), col("wrapped.email")).alias("principal_user_email"),
               coalesce(col("direct.iss"), col("wrapped.iss")).alias("principal_user_issuer"),
               coalesce(col("direct.roles"), col("wrapped.roles")).alias("principal_user_roles"),
               coalesce(col("direct.sudoed_by_id"), col("wrapped.sudoed_by_id")).alias("id_principal_user_impersonated_by"),
               coalesce(col("direct.sub"), col("wrapped.sub")).alias("principal_user_sub"),
               principal_identities_json.alias("principal_identities_json"),
               principal_service.alias("principal_service"),
               col("data.result.response_code_details").alias("response_code_details"),
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

    df = (
        spark.read
        .schema(OUTER_SCHEMA)
        .option("mode", "PERMISSIVE")
        .json(args.path.format(
            args.execution_date.year,
            str(args.execution_date.month).zfill(2),
            str(args.execution_date.day).zfill(2),
            str(args.execution_date.hour).zfill(2),
        ))
    )
    df = clean_cf(df)

    DeltaLoader().load_table(
        table_name=f"datalake_{args.schema}_clean.{args.table_name}",
        path=f"s3://{args.datalake_bucket}/clean/{args.schema}/{args.table_name}/",
        source_df=df,
        partition_by=args.partition_cols,
    )

def get_claims_schema():
    act_schema = StructType([
        StructField('sub', StringType(), True),
    ])

    return StructType([
        StructField('id', LongType(), True),
        StructField('sub', StringType(), True),
        StructField('act', act_schema, True),
        StructField('aud', StringType(), True),
        StructField('email', StringType(), True),
        StructField('personUUID', StringType(), True),
        StructField('name', StringType(), True),
        StructField('firstname', StringType(), True),
        StructField('iss', StringType(), True),
        StructField('roles', StringType(), True),
        StructField('jti', StringType(), True),
        StructField('exp', LongType(), True),
        StructField('iat', LongType(), True),
        StructField('creationDate', StringType(), True),
        StructField('userCreatedAt', StringType(), True),
        StructField('sudoed_by_id', LongType(), True),
        StructField('telefone', StringType(), True),
        StructField('titulo', StringType(), True),
    ])


def get_istio_schema():
    principal_info_schema = StructType([
        StructField('user', StringType(), True),
        StructField('service', StringType(), True),
    ])

    result_schema = StructType([
        StructField('principal_info', principal_info_schema, True),
        StructField('response_code_details', StringType(), True),
    ])

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
        StructField('duration', LongType(), True),
        StructField('result', result_schema, True),
    ])

if __name__ == "__main__":
    main()
