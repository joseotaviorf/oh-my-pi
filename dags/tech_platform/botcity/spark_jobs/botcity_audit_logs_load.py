import ast
from argparse import ArgumentParser

from dateutil import parser
from pyspark.sql import DataFrame
from pyspark.sql.functions import col, dayofmonth, hour, month, to_timestamp, year
from pyspark.sql.types import StringType, StructField, StructType
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import spark
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "botcity_audit_logs_load"
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
    add_validation_target_args(arg_parser)

    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partition_cols)
    args.execution_date = parser.parse(args.execution_date)

    config_service = ConfigurationService(args.source)
    args.path = config_service.get_config("path")

    return args


def clean_df(data_frame: "DataFrame") -> "DataFrame":
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
        hour(ts).alias("hour"),
    )

    data_frame = data_frame.dropDuplicates(["id_event"])

    return data_frame


def load_data_frame(path):
    """
    Loads BotCity audit logs from the given path.
    Returns an empty DataFrame if no files are found.

    :param path: S3 path to load data from (e.g. s3://datalake-botcity-audit-logs/year=2025/month=07/day=10/)
    :return: DataFrame with audit logs data or empty DataFrame
    """
    logger.info(
        f"m=load_data_frame, audit_logs_path={path}, msg=Attempting to load audit logs from path"
    )
    botcity_audit_logs_schema = StructType(
        [
            StructField(
                "user",
                StructType(
                    [
                        StructField("email", StringType(), True),
                        StructField("name", StringType(), True),
                    ]
                ),
                True,
            ),
            StructField("log_id", StringType(), True),
            StructField("source", StringType(), True),
            StructField("type", StringType(), True),
            StructField("organization", StringType(), True),
            StructField("date", StringType(), True),
            StructField(
                "params",
                StructType(
                    [
                        StructField("resource", StringType(), True),
                        StructField("name", StringType(), True),
                        StructField("id", StringType(), True),
                        StructField("automation", StringType(), True),
                        StructField("cron", StringType(), True),
                        StructField("version", StringType(), True),
                        StructField("releaseVersion", StringType(), True),
                    ]
                ),
                True,
            ),
        ]
    )

    try:
        df = spark.read.format("json").load(path, schema=botcity_audit_logs_schema)
        logger.info(
            f"m=load_data_frame, audit_logs_path={path}, msg=Successfully loaded audit logs from path"
        )
        return df
    except AnalysisException as e:
        if "PATH_NOT_FOUND" in str(e):
            logger.warning(
                f"m=load_data_frame, path={path}, msg=No audit log files found for the specified date, returning empty DataFrame, error={e}"
            )
            return spark.createDataFrame([], schema=botcity_audit_logs_schema)
        else:
            logger.error(
                f"m=load_data_frame, path={path}, msg=Unexpected AnalysisException, error={e}"
            )
            raise e


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
        f"year={args.execution_date.year}",
        f"month={args.execution_date.month:02}",
        f"day={args.execution_date.day:02}",
    )

    raw_data_frame = load_data_frame(audit_logs_path)

    if raw_data_frame.count() == 0:
        logger.warning(
            f"m=__main__, audit_logs_path={audit_logs_path}, "
            f"execution_date={args.execution_date}, msg=No audit logs found for the specified date. "
            f"Skipping data processing and load."
        )
        return

    logger.info(
        f"m=__main__, records_count={raw_data_frame.count()}, msg=Processing audit logs"
    )
    clean_data_frame = clean_df(raw_data_frame)

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
        write_path = (
            f"s3://{args.datalake_bucket}/clean/{args.schema}/{args.table_name}/"
        )

    logger.info(
        f"m=__main__, write_database={write_database_name}, "
        f"write_table={write_table_name}, write_path={write_path}"
    )

    DeltaLoader().load_table(
        table_name=f"{write_database_name}.{write_table_name}",
        path=write_path,
        source_df=clean_data_frame,
        partition_by=args.partition_cols,
        merge_on=["id_event"],
    )


if __name__ == "__main__":
    main()
