import ast
import json
from argparse import ArgumentParser

from dateutil import parser
from pyspark.sql.functions import col, dayofmonth, hour, month, to_timestamp, year
from pyspark.sql.types import ArrayType, MapType, StringType, StructField, StructType
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

JOB_NAME = "vault_request_load"
logger = QuintoAndarLogger(JOB_NAME)
_CLEAN_LAYER = LayerEnum.CLEAN.value


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
    args.output_path = config_service.get_config("output_path")

    return args


def load_df(input_path):
    events_schema = StructType(
        [
            StructField(
                "auth",
                StructType(
                    [
                        StructField("accessor", StringType(), True),
                        StructField("client_token", StringType(), True),
                        StructField("display_name", StringType(), True),
                        StructField("entity_id", StringType(), True),
                        StructField(
                            "metadata", MapType(StringType(), StringType()), True
                        ),
                        StructField("policies", ArrayType(StringType()), True),
                        StructField(
                            "policy_results",
                            StructType(
                                [
                                    StructField("allowed", StringType(), True),
                                    StructField(
                                        "granting_policies",
                                        ArrayType(
                                            StructType(
                                                [
                                                    StructField(
                                                        "name", StringType(), True
                                                    ),
                                                    StructField(
                                                        "namespace_id",
                                                        StringType(),
                                                        True,
                                                    ),
                                                    StructField(
                                                        "type", StringType(), True
                                                    ),
                                                ]
                                            )
                                        ),
                                        True,
                                    ),
                                ]
                            ),
                            True,
                        ),
                        StructField("token_issue_time", StringType(), True),
                        StructField("token_policies", ArrayType(StringType()), True),
                        StructField("token_ttl", StringType(), True),
                        StructField("token_type", StringType(), True),
                    ]
                ),
                True,
            ),
            StructField(
                "request",
                StructType(
                    [
                        StructField("client_id", StringType(), True),
                        StructField("client_token", StringType(), True),
                        StructField("client_token_accessor", StringType(), True),
                        StructField("id", StringType(), True),
                        StructField("mount_accessor", StringType(), True),
                        StructField("mount_point", StringType(), True),
                        StructField("mount_type", StringType(), True),
                        StructField(
                            "namespace",
                            StructType([StructField("id", StringType(), True)]),
                            True,
                        ),
                        StructField("operation", StringType(), True),
                        StructField("path", StringType(), True),
                        StructField("remote_address", StringType(), True),
                        StructField("remote_port", StringType(), True),
                    ]
                ),
                True,
            ),
            StructField(
                "response",
                StructType(
                    [
                        StructField(
                            "data",
                            StructType(
                                [
                                    StructField("accessor", StringType(), True),
                                    StructField("creation_time", StringType(), True),
                                    StructField("creation_ttl", StringType(), True),
                                    StructField("display_name", StringType(), True),
                                    StructField("entity_id", StringType(), True),
                                    StructField("expire_time", StringType(), True),
                                    StructField("explicit_max_ttl", StringType(), True),
                                    StructField("id", StringType(), True),
                                    StructField("issue_time", StringType(), True),
                                    StructField(
                                        "meta",
                                        MapType(StringType(), StringType()),
                                        True,
                                    ),
                                    StructField("num_uses", StringType(), True),
                                    StructField("orphan", StringType(), True),
                                    StructField("path", StringType(), True),
                                    StructField(
                                        "policies", ArrayType(StringType()), True
                                    ),
                                    StructField("renewable", StringType(), True),
                                    StructField("ttl", StringType(), True),
                                    StructField("type", StringType(), True),
                                ]
                            ),
                            True,
                        ),
                        StructField("mount_accessor", StringType(), True),
                        StructField("mount_point", StringType(), True),
                        StructField("mount_type", StringType(), True),
                    ]
                ),
                True,
            ),
            StructField("time", StringType(), True),
            StructField("type", StringType(), True),
        ]
    )
    return spark.read.format("json").load(input_path, schema=events_schema)


def clean_df(df):
    ts = to_timestamp(col("time"))
    return df.select(
        ts.alias("ts_event"),
        col("request.id").alias("id_request"),
        col("type"),
        col("time"),
        col("auth.display_name").alias("display_name"),
        col("auth.policies").alias("policies"),
        col("auth.token_policies").alias("token_policies"),
        col("auth.policy_results.allowed").alias("allowed"),
        col("auth.policy_results.granting_policies").alias("granting_policies"),
        col("auth.metadata.role").alias("role"),
        col("auth.entity_id").alias("entity_id"),
        col("auth.token_type").alias("token_type"),
        col("auth.token_ttl").alias("token_ttl"),
        col("auth.token_issue_time").alias("token_issue_time"),
        col("request.id").alias("request_id"),
        col("request.client_id").alias("client_id"),
        col("request.operation").alias("operation"),
        col("request.mount_point").alias("mount_point"),
        col("request.mount_type").alias("mount_type"),
        col("request.namespace.id").alias("namespace"),
        col("request.path").alias("path"),
        col("request.remote_address").alias("remote_address"),
        col("request.remote_port").alias("remote_port"),
        year(ts).alias("year"),
        month(ts).alias("month"),
        dayofmonth(ts).alias("day"),
        hour(ts).alias("hour"),
    ).where(col("time").isNotNull())


def main():
    """
    This DAG loads and cleans Vault audit events.
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
        f"{args.execution_date.year}/{args.execution_date.month:02}/{args.execution_date.day:02}/*.log.gz"
    )
    raw_df = load_df(input_path)
    df = clean_df(raw_df)

    database_name, database_location, _ = DatalakeMetastoreService.get_layer_info(
        args.env, args.schema, args.datalake_bucket, _CLEAN_LAYER
    )
    if args.target_database_name and args.target_table_name:
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
    else:
        write_database_name = database_name
        write_table_name = args.table_name
        write_path = f"{args.output_path}/clean/{args.schema}/{args.table_name}/"

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
