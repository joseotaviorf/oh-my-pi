import ast
import json
import logging
from argparse import ArgumentParser

from pyspark.sql.functions import col, current_timestamp, greatest, lit
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.base.spark import BaseDBUtils, SparkDataFrameService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import OracleConsumer
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message

JOB_NAME = "load_cyber_audit_log_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    arg_parser = ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("environment", help="forno/prod values")
    arg_parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    arg_parser.add_argument("source", help="name of the source")
    arg_parser.add_argument("table_name", help="name of the output table")
    arg_parser.add_argument("load_start_date", help="Start of date range: '%Y-%m-%d'")
    arg_parser.add_argument("load_end_date", help="End of date range: '%Y-%m-%d'")
    arg_parser.add_argument(
        "extraction_type", help="extraction_type - full or incremental"
    )
    arg_parser.add_argument("partitions", help="partition columns")
    arg_parser.add_argument("date_filter_columns", help="date filter columns")
    arg_parser.add_argument("purge_table", help="purge_table - True or False")
    arg_parser.add_argument(
        "excluded_fields",
        help="List of table fields that should not be ingested into the datalake",
    )
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

    args.partitions = ast.literal_eval(args.partitions)
    args.purge_table = ast.literal_eval(args.purge_table)
    args.date_filter_columns = ast.literal_eval(args.date_filter_columns)
    args.excluded_fields = ast.literal_eval(args.excluded_fields)

    config_service = ConfigurationService(args.source)
    args.output_path = config_service.get_config("output_path")

    return args


def _get_conn_config(dbutils, dbutils_secret_key):
    conn_config_json = dbutils.secrets.get(scope="quintoandar", key=dbutils_secret_key)
    return json.loads(conn_config_json)


def _send_warning(dbutils, environment, table_name):
    if environment == "prod":
        key = GchatWebhooksEnum.FINTECH_ALERTS_PROD
    else:
        key = GchatWebhooksEnum.AE_ALERTS_FORNO

    gchat_webhook = dbutils.secrets.get(scope="quintoandar", key=key)

    message_content = (
        f"⚠️\n"
        f"DAG: *Cyber Audit Log*\n"
        f"Environment: *{environment}*\n"
        f"Table: `{table_name}`\n"
        f"Status: *FAILED*\n"
        f"Error: *There is no data in Oracle database for table {table_name}*\n"
    )

    message = Message(content=message_content, destination=gchat_webhook)
    logger.info(f"m=__main__, message=sending gchat message: {message}")
    GChatService.send_message(message)


def load_df_from_oracle(
    oracle_consumer,
    table_name,
    extraction_type,
    date_filter_columns,
    load_start_date,
    load_end_date,
    excluded_fields,
    purge_table,
):
    """
    Loads data from Oracle database, handling purge table logic specific to Cyber system
    """
    oracle_table_name = table_name.upper()

    if extraction_type == "incremental" and date_filter_columns:
        df = oracle_consumer.get_incremental_data_from_table(
            oracle_table_name,
            date_filter_columns,
            load_start_date,
            load_end_date,
            excluded_fields,
        )
    else:
        df = oracle_consumer.get_data_from_table(oracle_table_name, excluded_fields)

    df = df.withColumn("source", lit("Original Table"))

    if purge_table:
        logger.info(
            f"m=load_df_from_oracle, msg=Loading purge table for {oracle_table_name}"
        )

        if extraction_type == "incremental" and date_filter_columns:
            df_purge = oracle_consumer.get_incremental_data_from_table(
                f"{oracle_table_name}_ESP",
                date_filter_columns,
                load_start_date,
                load_end_date,
                excluded_fields,
            )
        else:
            df_purge = oracle_consumer.get_data_from_table(
                f"{oracle_table_name}_ESP", excluded_fields
            )

        df_purge = df_purge.withColumn("source", lit("Purge Table"))

        existing_columns = set(df.columns)
        new_columns = set(df_purge.columns)

        missing_in_existing = new_columns - existing_columns
        missing_in_new = existing_columns - new_columns

        for column_missing_existing in missing_in_existing:
            df = df.withColumn(column_missing_existing, lit(None))

        for column_missing_new in missing_in_new:
            df_purge = df_purge.withColumn(column_missing_new, lit(None))

        df = df.unionByName(df_purge)
        logger.info(
            "m=load_df_from_oracle, msg=Successfully merged main and purge tables"
        )

    return df


def add_partition(df, date_filter_columns):
    """
    Prepare DataFrame for loading, adding necessary columns for partitioning
    """
    if df.count() == 0:
        return df

    df = df.withColumn("ts_ingestion", current_timestamp())

    if date_filter_columns:
        if len(date_filter_columns) > 1:
            df = df.withColumn(
                "table_partition", (greatest(*[col(c) for c in date_filter_columns]))
            )
        else:
            df = df.withColumn("table_partition", (col(date_filter_columns[0])))
        partition = "table_partition"
    else:
        partition = "ts_ingestion"

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column(partition)
        .output()
    )

    return df


def main():
    """
    This DAG loads Cyber audit logs from Oracle database.
    """
    args = parse_arguments()
    if args.table_privileges is not None:
        table_privileges_dict = json.loads(args.table_privileges)
    else:
        table_privileges_dict = None

    logger.info(
        f"""
        m=__main__, environment={args.environment}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket}, source={args.source},
        table_name={args.table_name}, extraction_type={args.extraction_type},
        purge_table={args.purge_table}, output_path={args.output_path},
        msg=Starting spark job...
        """
    )

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()
    conn_config = _get_conn_config(dbutils, DatabaseEnum.CYBER)

    spark_client = SparkClient()
    oracle_consumer = OracleConsumer(conn_config, spark_client)

    raw_df = load_df_from_oracle(
        oracle_consumer,
        args.table_name,
        args.extraction_type,
        args.date_filter_columns,
        args.load_start_date,
        args.load_end_date,
        args.excluded_fields,
        args.purge_table,
    )

    if raw_df.count() == 0:
        _send_warning(dbutils, args.environment, args.table_name)
        logger.warning(f"m=__main__, msg=No data found for table {args.table_name}")
        return

    df = add_partition(raw_df, args.date_filter_columns)

    prod_database = f"datalake_{args.source}_raw"
    prod_location = f"{args.output_path}/raw/"
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=prod_database,
            prod_table=args.table_name,
            prod_location=prod_location,
            bucket=args.datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )
    full_raw_table_name = f"{write_database_name}.{write_table_name}"
    if table_privileges_dict is not None:
        table_privileges = TablePrivileges.from_input_dict(
            table_privileges_dict, full_raw_table_name
        )
    else:
        table_privileges = TablePrivileges.from_environment_default(
            f"{write_database_name}.{write_table_name}"
        )

    DeltaLoader(spark_client.conn).load_table(
        table_name=full_raw_table_name,
        path=f"{write_location}{write_table_name}/",
        source_df=df,
        partition_by=args.partitions,
    )

    if table_privileges and UnityCatalogHelper.is_cluster_unity_catalog_enabled():
        table_privileges.apply()

    logger.info(f"m=__main__, msg=Successfully loaded table {full_raw_table_name}")


if __name__ == "__main__":
    main()
