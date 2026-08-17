import ast
from argparse import ArgumentParser
from datetime import timedelta
from functools import reduce

from dateutil import parser
from pyspark.sql import DataFrame
from pyspark.sql.functions import col, lit, to_timestamp
from pyspark.sql.types import LongType, StringType, StructField, StructType
from pyspark.sql.utils import AnalysisException
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

JOB_NAME = "olos_dialer_transcriptions_load"
logger = QuintoAndarLogger(JOB_NAME)
_CLEAN_LAYER = LayerEnum.CLEAN.value
# S3 producer contract (MonalisaAudioAITranscriptionPerformer): each transcription is
# written as <id_call>.ndjson.gz inside the call-date partition (year/month/day of the
# call), and a re-analysis OVERWRITES that same file. So within any partition each
# id_call is unique and always holds the latest analysis. Two consequences relied on
# below: dedup by id_call is only a safety net (no real duplicates in a batch), and the
# Delta merge can update unconditionally -- re-reading a partition (daily or backfill)
# always yields the authoritative latest, so clean only ever moves forward.
_MERGE_ON = ["id_call"]

TRANSCRIPTIONS_SCHEMA = StructType(
    [
        StructField("id_call", LongType(), True),
        StructField("analysis_id", StringType(), True),
        StructField("ts_analysis", StringType(), True),
        StructField("transcription", StringType(), True),
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


def clean_df(data_frame: "DataFrame", audio_date) -> "DataFrame":
    """
    Select and normalize the transcription columns (analysis_id -> id_analysis,
    ts_analysis -> ts_analyzed timestamp), partition by the audio/call date (audio_date)
    and deduplicate by id_call.
    """
    data_frame = data_frame.select(
        col("id_call"),
        col("analysis_id").alias("id_analysis"),
        col("transcription"),
        to_timestamp(col("ts_analysis")).alias("ts_analyzed"),
        lit(audio_date.year).alias("year"),
        lit(audio_date.month).alias("month"),
        lit(audio_date.day).alias("day"),
    )

    data_frame = data_frame.dropDuplicates(_MERGE_ON)

    return data_frame


def load_data_frame(path):
    """
    Loads Olos dialer transcriptions from the given path.
    Returns an empty DataFrame if no files are found (empty S3 day partition).

    :param path: S3 glob path to load data from
        (e.g. s3://monalisa-prod/transcriptions/year=2026/month=07/day=01/*.ndjson.gz)
    :return: DataFrame with transcriptions data or empty DataFrame
    """
    logger.info(
        f"m=load_data_frame, transcriptions_path={path}, msg=Attempting to load transcriptions from path"
    )

    try:
        df = spark.read.format("json").load(path, schema=TRANSCRIPTIONS_SCHEMA)
        logger.info(
            f"m=load_data_frame, transcriptions_path={path}, msg=Successfully loaded transcriptions from path"
        )
        return df
    except AnalysisException as e:
        if "PATH_NOT_FOUND" in str(e):
            logger.warning(
                f"m=load_data_frame, path={path}, msg=No transcription files found for the specified date, returning empty DataFrame, error={e}"
            )
            return spark.createDataFrame([], schema=TRANSCRIPTIONS_SCHEMA)
        else:
            logger.error(
                f"m=load_data_frame, path={path}, msg=Unexpected AnalysisException, error={e}"
            )
            raise e


def main():
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

    # Process each audio/call day in [load_start_date, load_end_date] — a single day for
    # the daily schedule (default), or a range for backfill (dates from the run conf).
    audio_dates = [
        args.load_start_date + timedelta(days=n)
        for n in range((args.load_end_date - args.load_start_date).days + 1)
    ]
    day_frames = []
    for audio_date in audio_dates:
        transcriptions_path = args.path.format(
            f"year={audio_date.year}",
            f"month={audio_date.month:02}",
            f"day={audio_date.day:02}",
        )
        raw_data_frame = load_data_frame(transcriptions_path)
        records_count = raw_data_frame.count()
        logger.info(
            f"m=__main__, audio_date={audio_date.date()}, records_count={records_count}, msg=Read transcriptions partition"
        )
        if records_count > 0:
            day_frames.append(clean_df(raw_data_frame, audio_date))

    if not day_frames:
        logger.warning(
            f"m=__main__, load_start_date={args.load_start_date.date()}, "
            f"load_end_date={args.load_end_date.date()}, "
            f"msg=No transcriptions found in the date range. Skipping data processing and load."
        )
        return

    clean_data_frame = reduce(DataFrame.unionAll, day_frames).dropDuplicates(_MERGE_ON)

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
