import ast
from argparse import ArgumentParser
from datetime import timedelta
from functools import reduce

from dateutil import parser
from pyspark.sql import DataFrame, Window
from pyspark.sql.functions import col, explode, lit, row_number, to_timestamp
from pyspark.sql.types import (
    ArrayType,
    BooleanType,
    LongType,
    StringType,
    StructField,
    StructType,
)
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

JOB_NAME = "monalisa_monitoria_evaluations_load"
logger = QuintoAndarLogger(JOB_NAME)
_CLEAN_LAYER = LayerEnum.CLEAN.value

_HEADER_TABLE = "monalisa_monitoria_evaluations"
_CRITERIA_TABLE = "monalisa_monitoria_evaluation_criteria"
_NCGS_TABLE = "monalisa_monitoria_evaluation_ncgs"

_MERGE_ON = {
    _HEADER_TABLE: ["id_reference"],
    _CRITERIA_TABLE: ["id_reference", "criterion"],
    _NCGS_TABLE: ["id_reference", "criterion"],
}

_ITEM_SCHEMA = StructType(
    [
        StructField("criterio", StringType(), True),
        StructField("conformidade", StringType(), True),
        StructField("justificativa", StringType(), True),
    ]
)

EVALUATIONS_SCHEMA = StructType(
    [
        StructField("analysis_id", StringType(), True),
        StructField("reference_id", LongType(), True),
        StructField("ts_analysis", StringType(), True),
        StructField("origin_flow", StringType(), True),
        StructField("resumo", StringType(), True),
        StructField("convertido", BooleanType(), True),
        StructField("email_analista", StringType(), True),
        StructField("feedback", StringType(), True),
        StructField("analise_intent_cliente", StringType(), True),
        StructField("qualidade_lead", StringType(), True),
        StructField("pontos_positivos", ArrayType(StringType()), True),
        StructField("pontos_de_melhoria", ArrayType(StringType()), True),
        StructField(
            "analise_de_audio",
            StructType(
                [
                    StructField("teve_audio", BooleanType(), True),
                    StructField("impacto_na_monitoria", BooleanType(), True),
                    StructField("nivel_de_confianca", StringType(), True),
                    StructField("justificativa_da_inferencia", StringType(), True),
                ]
            ),
            True,
        ),
        StructField("checklist", ArrayType(_ITEM_SCHEMA), True),
        StructField("ncgs", ArrayType(_ITEM_SCHEMA), True),
    ]
)


def base_df(data_frame: "DataFrame", partition_date) -> "DataFrame":
    return data_frame.select(
        col("reference_id").cast(LongType()).alias("id_reference"),
        col("analysis_id").alias("uuid_analysis"),
        col("origin_flow"),
        to_timestamp(col("ts_analysis")).alias("ts_analysis"),
        col("resumo"),
        col("convertido"),
        col("email_analista"),
        col("feedback"),
        col("analise_intent_cliente"),
        col("qualidade_lead"),
        col("pontos_positivos"),
        col("pontos_de_melhoria"),
        col("analise_de_audio"),
        col("checklist"),
        col("ncgs"),
        lit(partition_date.year).alias("year"),
        lit(partition_date.month).alias("month"),
        lit(partition_date.day).alias("day"),
    )


def deduplicate_latest_analysis(data_frame: "DataFrame") -> "DataFrame":
    """Keep the latest analysis per conversation: a rerun keeps id_reference but mints a new uuid_analysis."""
    window = Window.partitionBy("id_reference").orderBy(
        col("ts_analysis").desc_nulls_last()
    )
    return (
        data_frame.withColumn("_rn", row_number().over(window))
        .filter(col("_rn") == 1)
        .drop("_rn")
    )


def header_df(data_frame: "DataFrame") -> "DataFrame":
    return data_frame.select(
        col("id_reference"),
        col("uuid_analysis"),
        col("origin_flow"),
        col("resumo").alias("summary"),
        col("email_analista").alias("email_primary_analyst"),
        col("feedback"),
        col("pontos_positivos").alias("strengths"),
        col("pontos_de_melhoria").alias("improvement_areas"),
        col("analise_intent_cliente").alias("client_intent_analysis"),
        col("qualidade_lead").alias("lead_quality"),
        col("analise_de_audio.nivel_de_confianca").alias("audio_confidence_level"),
        col("analise_de_audio.justificativa_da_inferencia").alias(
            "audio_inference_justification"
        ),
        col("convertido").alias("is_converted"),
        col("analise_de_audio.teve_audio").alias("has_audio"),
        col("analise_de_audio.impacto_na_monitoria").alias("has_audio_impact"),
        col("ts_analysis"),
        col("year"),
        col("month"),
        col("day"),
    )


def _explode_items(data_frame: "DataFrame", array_column: str) -> "DataFrame":
    exploded = data_frame.select(
        col("id_reference"),
        col("year"),
        col("month"),
        col("day"),
        explode(col(array_column)).alias("item"),
    )
    return exploded.select(
        col("id_reference"),
        col("item.criterio").alias("criterion"),
        col("item.conformidade").alias("conformity"),
        col("item.justificativa").alias("justification"),
        col("year"),
        col("month"),
        col("day"),
    )


def criteria_df(data_frame: "DataFrame") -> "DataFrame":
    return _explode_items(data_frame, "checklist")


def ncgs_df(data_frame: "DataFrame") -> "DataFrame":
    return _explode_items(data_frame, "ncgs")


_TRANSFORMS = {
    _HEADER_TABLE: header_df,
    _CRITERIA_TABLE: criteria_df,
    _NCGS_TABLE: ncgs_df,
}


def load_data_frame(path):
    """Return the day's evaluations, or an empty DataFrame when the S3 partition is absent."""
    logger.info(
        f"m=load_data_frame, evaluations_path={path}, msg=Attempting to load evaluations from path"
    )

    try:
        df = spark.read.format("json").load(path, schema=EVALUATIONS_SCHEMA)
        logger.info(
            f"m=load_data_frame, evaluations_path={path}, msg=Successfully loaded evaluations from path"
        )
        return df
    except AnalysisException as e:
        message = str(e)
        if "PATH_NOT_FOUND" in message or "Path does not exist" in message:
            logger.warning(
                f"m=load_data_frame, path={path}, msg=No evaluation files found for the specified date, returning empty DataFrame, error={e}"
            )
            return spark.createDataFrame([], schema=EVALUATIONS_SCHEMA)
        else:
            logger.error(
                f"m=load_data_frame, path={path}, msg=Unexpected AnalysisException, error={e}"
            )
            raise e


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

    if args.table_name not in _TRANSFORMS:
        raise ValueError(
            f"Unsupported table_name '{args.table_name}'. Expected one of {sorted(_TRANSFORMS)}."
        )

    config_service = ConfigurationService(args.source)
    args.path = config_service.get_config("path")

    return args


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

    merge_on = _MERGE_ON[args.table_name]
    transform = _TRANSFORMS[args.table_name]

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
            day_frames.append(base_df(raw_data_frame, partition_date))

    if not day_frames:
        logger.warning(
            f"m=__main__, load_start_date={args.load_start_date.date()}, "
            f"load_end_date={args.load_end_date.date()}, "
            f"msg=No evaluations found in the date range. Skipping data processing and load."
        )
        return

    winning_analyses = deduplicate_latest_analysis(
        reduce(DataFrame.unionAll, day_frames)
    )
    clean_data_frame = transform(winning_analyses).dropDuplicates(merge_on)

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
        merge_on=merge_on,
    )


if __name__ == "__main__":
    main()
