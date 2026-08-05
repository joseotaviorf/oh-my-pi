import ast
import json
from argparse import ArgumentParser

from dateutil import parser
from pyspark.sql.functions import (
    col,
    dayofmonth,
    from_json,
    get_json_object,
    hour,
    month,
    to_timestamp,
    year,
)
from pyspark.sql.types import ArrayType, StringType, StructField, StructType
from pyspark.sql.utils import AnalysisException
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

JOB_NAME = "okta_system_logs_load"
logger = QuintoAndarLogger(JOB_NAME)
_CLEAN_LAYER = LayerEnum.CLEAN.value

_TARGET_SCHEMA = ArrayType(
    StructType(
        [
            StructField("id", StringType(), True),
            StructField("type", StringType(), True),
            StructField("alternateId", StringType(), True),
            StructField("displayName", StringType(), True),
        ]
    )
)

_OKTA_DETAIL_SCHEMA = StructType(
    [
        StructField("uuid", StringType(), True),
        StructField("published", StringType(), True),
        StructField("eventType", StringType(), True),
        StructField("displayMessage", StringType(), True),
        StructField("severity", StringType(), True),
        StructField("legacyEventType", StringType(), True),
        StructField(
            "outcome",
            StructType(
                [
                    StructField("result", StringType(), True),
                    StructField("reason", StringType(), True),
                ]
            ),
            True,
        ),
        StructField(
            "actor",
            StructType(
                [
                    StructField("id", StringType(), True),
                    StructField("type", StringType(), True),
                    StructField("alternateId", StringType(), True),
                    StructField("displayName", StringType(), True),
                ]
            ),
            True,
        ),
        StructField(
            "client",
            StructType(
                [
                    StructField("ipAddress", StringType(), True),
                    StructField("device", StringType(), True),
                    StructField(
                        "userAgent",
                        StructType(
                            [
                                StructField("rawUserAgent", StringType(), True),
                                StructField("browser", StringType(), True),
                                StructField("os", StringType(), True),
                            ]
                        ),
                        True,
                    ),
                    StructField(
                        "geographicalContext",
                        StructType(
                            [
                                StructField("city", StringType(), True),
                                StructField("country", StringType(), True),
                            ]
                        ),
                        True,
                    ),
                ]
            ),
            True,
        ),
        StructField(
            "transaction",
            StructType(
                [
                    StructField("id", StringType(), True),
                    StructField("type", StringType(), True),
                ]
            ),
            True,
        ),
        StructField("target", _TARGET_SCHEMA, True),
    ]
)

_ENVELOPE_SCHEMA = StructType(
    [
        StructField("id", StringType(), True),
        StructField("source", StringType(), True),
        StructField("detail-type", StringType(), True),
        StructField("detail", StringType(), True),
    ]
)


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
    args.input_path = config_service.get_config("input_path")
    args.tenant = config_service.get_config("tenant") or "sandbox"

    return args


def load_df(input_path):
    try:
        return spark.read.format("json").load(input_path, schema=_ENVELOPE_SCHEMA)
    except AnalysisException as exc:
        if "PATH_NOT_FOUND" in str(exc):
            logger.warning(
                f"m=load_df, path={input_path}, msg=No Okta log files found, "
                f"returning empty DataFrame, error={exc}"
            )
            return spark.createDataFrame([], schema=_ENVELOPE_SCHEMA)
        raise


def clean_df(df):
    parsed = df.withColumn(
        "detail_parsed", from_json(col("detail"), _OKTA_DETAIL_SCHEMA)
    )
    ts = to_timestamp(col("detail_parsed.published"))
    return parsed.select(
        ts.alias("ts_event"),
        col("detail_parsed.uuid").alias("id_event"),
        col("detail_parsed.eventType").alias("event_type"),
        col("detail_parsed.displayMessage").alias("display_message"),
        col("detail_parsed.severity").alias("severity"),
        col("detail_parsed.legacyEventType").alias("legacy_event_type"),
        col("detail_parsed.outcome.result").alias("outcome_result"),
        col("detail_parsed.outcome.reason").alias("outcome_reason"),
        col("detail_parsed.actor.id").alias("actor_id"),
        col("detail_parsed.actor.type").alias("actor_type"),
        col("detail_parsed.actor.alternateId").alias("actor_alternate_id"),
        col("detail_parsed.actor.displayName").alias("actor_display_name"),
        col("detail_parsed.client.ipAddress").alias("client_ip_address"),
        col("detail_parsed.client.userAgent.rawUserAgent").alias("client_user_agent"),
        col("detail_parsed.client.userAgent.browser").alias("client_browser"),
        col("detail_parsed.client.userAgent.os").alias("client_os"),
        col("detail_parsed.client.device").alias("client_device"),
        col("detail_parsed.client.geographicalContext.city").alias("client_city"),
        col("detail_parsed.client.geographicalContext.country").alias("client_country"),
        col("detail_parsed.transaction.id").alias("transaction_id"),
        col("detail_parsed.transaction.type").alias("transaction_type"),
        col("id").alias("id_eventbridge"),
        col("source").alias("eventbridge_source"),
        col("`detail-type`").alias("eventbridge_detail_type"),
        col("detail_parsed.target").alias("target"),
        get_json_object(col("detail"), "$.debugContext").alias("js_debug_context"),
        year(ts).alias("year"),
        month(ts).alias("month"),
        dayofmonth(ts).alias("day"),
        hour(ts).alias("hour"),
    ).where(col("detail_parsed.published").isNotNull())


def main():
    """
    Load and clean Okta System Log events from the audit-logs S3 bucket.
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
        schema={args.schema}, table_name={args.table_name}, tenant={args.tenant},
        msg=Starting spark job...
        """
    )

    input_path = (
        f"{args.input_path}/{args.tenant}/raw/"
        f"{args.execution_date.year}/{args.execution_date.month:02}/"
        f"{args.execution_date.day:02}/*.gz"
    )
    raw_df = load_df(input_path)
    df = clean_df(raw_df)

    if df.isEmpty():
        logger.warning(
            f"m=__main__, input_path={input_path}, msg=No Okta system logs found; "
            f"skipping load"
        )
        return

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
    write_path = f"{write_location.rstrip('/')}/{write_table_name}"

    full_table_name = managed_table_fqn(
        prod_database=database_name,
        prod_table=args.table_name,
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )
    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, full_table_name
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(full_table_name)

    logger.info(
        f"m=__main__, write_database={write_database_name}, "
        f"write_table={write_table_name}, write_path={write_path}"
    )

    DeltaLoader().load_table(
        table_name=f"{write_database_name}.{write_table_name}",
        path=write_path,
        source_df=df,
        partition_by=args.partition_cols,
    )
    if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        table_privileges.apply()


if __name__ == "__main__":
    main()
