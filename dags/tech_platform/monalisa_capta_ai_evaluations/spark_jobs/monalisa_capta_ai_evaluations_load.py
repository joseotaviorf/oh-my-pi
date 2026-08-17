import ast
from argparse import ArgumentParser
from datetime import timedelta
from functools import reduce

from dateutil import parser
from pyspark.sql import DataFrame, Window
from pyspark.sql.functions import col, lit, row_number, to_date, to_timestamp
from pyspark.sql.types import (
    BooleanType,
    DoubleType,
    LongType,
    StringType,
    StructField,
    StructType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.spark import spark
from bietlejuice.base.spark.delta_secondary_catalog_sync import (
    partition_columns_present,
    sync_delta_write_to_secondary_catalog,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "monalisa_capta_ai_evaluations_load"
logger = QuintoAndarLogger(JOB_NAME)
_CLEAN_LAYER = LayerEnum.CLEAN.value
_MERGE_ON = ["id_reference"]

# The persisted record is the validated LLM output nested under `output`, plus the
# reference/analysis metadata added by build_evaluation_record in the RPA:
#   {"output": {oportunidade, categoria, resumo, abordagem, percentual},
#    "reference_id": <conversation id>, "analysis_id": <queue item id>,
#    "ts_analysis": "YYYY-MM-DD HH:MM:SS"}
_TS_FORMAT = "yyyy-MM-dd HH:mm:ss"
EVALUATIONS_SCHEMA = StructType(
    [
        StructField("reference_id", LongType(), True),
        StructField("analysis_id", StringType(), True),
        StructField("ts_analysis", StringType(), True),
        StructField(
            "output",
            StructType(
                [
                    StructField("oportunidade", BooleanType(), True),
                    StructField("categoria", StringType(), True),
                    StructField("resumo", StringType(), True),
                    StructField("abordagem", StringType(), True),
                    StructField("percentual", DoubleType(), True),
                ]
            ),
            True,
        ),
    ]
)


def parse_arguments():
    arg_parser = ArgumentParser(description=JOB_NAME)
    arg_parser.add_argument("source")
    arg_parser.add_argument("env")
    arg_parser.add_argument("datalake_bucket")
    arg_parser.add_argument("schema")
    arg_parser.add_argument("load_start_date")
    arg_parser.add_argument("load_end_date")
    arg_parser.add_argument("table_name")
    arg_parser.add_argument("partition_cols")
    add_validation_target_args(arg_parser)

    args = arg_parser.parse_args()
    args.partition_cols = ast.literal_eval(args.partition_cols)
    args.load_start_date = parser.parse(args.load_start_date)
    args.load_end_date = parser.parse(args.load_end_date)

    config_service = ConfigurationService(args.source)
    args.path = config_service.get_config("path")

    return args


def clean_df(data_frame: "DataFrame", partition_date) -> "DataFrame":
    """
    Flatten the nested `output` struct and normalize the Capta AI evaluation columns
    (Portuguese source names -> English clean names), partition by the S3 day partition
    date (partition_date) and keep the latest analysis per id_reference.
    """
    ts_analyzed = to_timestamp(col("ts_analysis"), _TS_FORMAT)

    data_frame = data_frame.select(
        col("reference_id").alias("id_reference"),
        col("analysis_id").alias("id_analysis"),
        col("output.categoria").alias("category"),
        col("output.resumo").alias("summary"),
        col("output.abordagem").alias("approach"),
        col("output.oportunidade").alias("is_opportunity"),
        col("output.percentual").alias("opportunity_score"),
        ts_analyzed.alias("ts_analyzed"),
        to_date(ts_analyzed).alias("dt_analyzed"),
        lit(partition_date.year).alias("year"),
        lit(partition_date.month).alias("month"),
        lit(partition_date.day).alias("day"),
    )

    data_frame = _keep_latest_per_conversation(data_frame)

    return data_frame


def _keep_latest_per_conversation(data_frame: "DataFrame") -> "DataFrame":
    """Keep a single row per id_reference: the latest analysis (max ts_analyzed)."""
    latest = Window.partitionBy(*_MERGE_ON).orderBy(
        col("ts_analyzed").desc_nulls_last()
    )
    return (
        data_frame.withColumn("_row_number", row_number().over(latest))
        .filter(col("_row_number") == 1)
        .drop("_row_number")
    )


def load_data_frame(path):
    """
    Loads Capta AI evaluations from the given path.
    Returns an empty DataFrame if no files are found (empty S3 day partition).

    :param path: S3 glob path to load data from
        (e.g. s3://monalisa-prod/evaluations/CaptaAi/year=2026/month=07/day=16/*.ndjson.gz)
    :return: DataFrame with evaluations data or empty DataFrame
    """
    logger.info(
        f"m=load_data_frame, evaluations_path={path}, msg=Attempting to load evaluations from path"
    )

    try:
        df = spark.read.format("json").load(path, schema=EVALUATIONS_SCHEMA)
        logger.info(
            f"m=load_data_frame, evaluations_path={path}, msg=Successfully loaded evaluations from path"
        )
        return df
    except Exception as e:
        # EMR raises "Path does not exist"; Databricks raises PATH_NOT_FOUND -- both mean
        # an empty S3 day partition, which we skip.
        error_message = str(e)
        if "Path does not exist" in error_message or "PATH_NOT_FOUND" in error_message:
            logger.warning(
                f"m=load_data_frame, path={path}, msg=No evaluation files found for the specified date, returning empty DataFrame, error={e}"
            )
            return spark.createDataFrame([], schema=EVALUATIONS_SCHEMA)
        logger.error(f"m=load_data_frame, path={path}, msg=Unexpected error, error={e}")
        raise


def main():
    """
    This DAG loads and cleans Capta AI conversation evaluations.
    """
    args = parse_arguments()
    logger.info(
        f"""
        m=__main__, environment={args.env}, dag_name={JOB_NAME}
        datalake_bucket={args.datalake_bucket},
        load_start_date={args.load_start_date.date()}, load_end_date={args.load_end_date.date()},
        schema={args.schema}, table_name={args.table_name},
        msg=Starting spark job...
        """
    )

    partition_dates = [
        args.load_start_date + timedelta(days=n)
        for n in range((args.load_end_date - args.load_start_date).days + 1)
    ]
    day_frames = []
    for partition_date in partition_dates:
        evaluations_path = args.path.format(
            f"year={partition_date.year}",
            f"month={partition_date.month:02}",
            f"day={partition_date.day:02}",
        )
        raw_data_frame = load_data_frame(evaluations_path)
        records_count = raw_data_frame.count()
        logger.info(
            f"m=__main__, partition_date={partition_date.date()}, records_count={records_count}, msg=Read evaluations partition"
        )
        if records_count > 0:
            day_frames.append(clean_df(raw_data_frame, partition_date))

    if not day_frames:
        logger.warning(
            f"m=__main__, load_start_date={args.load_start_date.date()}, "
            f"load_end_date={args.load_end_date.date()}, "
            f"msg=No evaluations found in the date range. Skipping data processing and load."
        )
        return

    clean_data_frame = _keep_latest_per_conversation(
        reduce(DataFrame.unionAll, day_frames)
    )

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
        merge_on=_MERGE_ON,
    )

    sync_delta_write_to_secondary_catalog(
        spark,
        f"{write_database_name}.{write_table_name}",
        write_path,
        clean_data_frame,
        partition_columns_present(clean_data_frame, args.partition_cols),
    )


if __name__ == "__main__":
    main()
