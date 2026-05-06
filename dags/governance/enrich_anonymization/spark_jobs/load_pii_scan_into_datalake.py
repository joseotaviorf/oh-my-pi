import argparse
import ast
from datetime import datetime
from typing import Dict, Iterable, Iterator, List, Tuple

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services import ConfigurationService
from presidio_analyzer import (
    AnalyzerEngine,
    BatchAnalyzerEngine,
    RecognizerRegistry,
)
from presidio_analyzer.nlp_engine import NlpEngineProvider
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, collect_list, count, explode, struct, to_json
from pyspark.sql.types import (
    ArrayType,
    IntegerType,
    MapType,
    StringType,
    StructField,
    StructType,
)
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_pii_scan_into_datalake"
logger = QuintoAndarLogger(JOB_NAME)

SCORE_THRESHOLD = 0.6

ENTITIES_LIST = [
    "BRAZIL_RG",  # Custom entity
    "BRAZIL_CPF",  # Custom entity
    "LOCATION",  # Custom entity
    "CREDIT_CARD",
    "EMAIL_ADDRESS",
    "IP_ADDRESS",
    "PERSON",
    "PHONE_NUMBER",
    "URL",
    "DATE_TIME",
    "BRAZIL_CNPJ",
]

COLUMN_NAME_ENTITIES = [
    "BRAZIL_CPF",  # Custom entity
    "PHONE_NUMBER",  # Custom entity
    "EMAIL_ADDRESS",  # Custom entity
    "PERSON",  # Custom entity
    "BIRTH_DATE",  # Custom entity
    "LOCATION",
    "BRAZIL_RG",  # Custom entity
    "BRAZIL_CNPJ",  # Custom entity
]

LABELS_TO_IGNORE = {
    "O",
    "ORG",
    "ORGANIZATION",
    "CARDINAL",
    "EVENT",
    "LANGUAGE",
    "LAW",
    "MONEY",
    "ORDINAL",
    "PERCENT",
    "PRODUCT",
    "QUANTITY",
    "WORK_OF_ART",
    "FAC",
}


def load_recognizers_from_dict(recognizer_dict_list) -> RecognizerRegistry:
    """
    Load custom recognizers from a YAML configuration file and add them to the registry.

    Returns:
        registry: A RecognizerRegistry instance with the custom recognizers loaded.
    """
    if not recognizer_dict_list:
        raise Exception("dict_recognizer_list is required.")

    registry = RecognizerRegistry()
    registry.load_predefined_recognizers()
    for dict_recognizer in recognizer_dict_list:
        registry.add_pattern_recognizer_from_dict(dict_recognizer)

    return registry


def load_nlp_config() -> Dict:
    """
    Load the NLP engine configuration.

    Returns:
        dict: A dictionary containing the NLP engine configuration.
    """
    nlp_config = {
        "nlp_engine_name": "spacy",
        "models": [{"lang_code": "en", "model_name": "en_core_web_lg"}],
        "ner_model_configuration": {"labels_to_ignore": LABELS_TO_IGNORE},
    }

    return nlp_config


def build_batch_analyzer(registry) -> BatchAnalyzerEngine:
    """
    Build and return a BatchAnalyzerEngine instance.

    Returns:
        BatchAnalyzerEngine: An instance of BatchAnalyzerEngine configured with the custom recognizers and NLP engine.
    """
    nlp_config = load_nlp_config()
    provider = NlpEngineProvider(nlp_configuration=nlp_config)

    nlp_engine = provider.create_engine()

    analyzer = AnalyzerEngine(nlp_engine=nlp_engine, registry=registry)
    batch_analyzer = BatchAnalyzerEngine(analyzer_engine=analyzer)

    return batch_analyzer


def clean_result(result, matched_value):
    if not result:
        return [
            {
                "type": "NOT_FOUND"
                if matched_value != "SAMPLE_TOO_BIG"
                else "SAMPLE_TOO_BIG",
                "score": 0.0,
                "matched_value": matched_value,
            }
        ]
    return [
        {
            "type": r.entity_type
            if matched_value != "SAMPLE_TOO_BIG"
            else "SAMPLE_TOO_BIG",
            "score": r.score,
            "matched_value": matched_value,
        }
        for r in result
    ]


def _rows_to_analyzer_inputs(rows_list: List) -> Tuple[Dict, Dict]:
    df_dict = {
        row["id_entity"]: row["sample"]
        if row["len_sample"] < 4000
        else ["SAMPLE_TOO_BIG"]
        for row in rows_list
    }
    df_dict_columns = {row["id_entity"]: row["list_column_name"] for row in rows_list}
    return df_dict, df_dict_columns


def make_process_partition(recognizer_dict_list):
    """
    Build a mapPartitions callable that constructs Presidio once per Spark partition.

    BatchAnalyzerEngine / spaCy are not reliably serializable across executors;
    initializing on the worker matches common Spark patterns for Python NLP stacks.
    """

    def process_partition(iter_of_rows: Iterable) -> Iterator:
        rows_list = list(iter_of_rows)
        if not rows_list:
            return

        registry = load_recognizers_from_dict(recognizer_dict_list)
        batch_analyzer = build_batch_analyzer(registry)

        df_dict, df_dict_columns = _rows_to_analyzer_inputs(rows_list)

        results = list(
            batch_analyzer.analyze_dict(
                input_dict=df_dict,
                entities=ENTITIES_LIST,
                score_threshold=SCORE_THRESHOLD,
                language="en",
            )
        )

        col_results = list(
            batch_analyzer.analyze_dict(
                input_dict=df_dict_columns,
                entities=COLUMN_NAME_ENTITIES,
                score_threshold=SCORE_THRESHOLD,
                language="en",
            )
        )
        for col_result, result, row in zip(col_results, results, rows_list):
            yield (
                *row,
                [
                    clean_result(r, matched_value)
                    for (r, matched_value) in zip(
                        result.recognizer_results, result.value
                    )
                ],
                [
                    clean_result(c, c_matched_value)
                    for (c, c_matched_value) in zip(
                        col_result.recognizer_results, col_result.value
                    )
                ],
            )

    return process_partition


def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
    partition_cols: list,
) -> None:
    logger.info("m=load_table,msg='loading table'")

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    loader = DeltaLoader()
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}/{table_name}",
        source_df=dataframe,
        partition_by=partition_cols,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument(
        "schema", help="name of the schema of the table to be saved in the data lake"
    )
    parser.add_argument(
        "table_name", help="name of the table to be saved in the data lake"
    )
    parser.add_argument(
        "load_start_date", help="timestamp of the ingest to get the sample from"
    )
    parser.add_argument("partitions", type=str)
    parser.add_argument("source", type=str)
    parser.add_argument(
        "--max_workers",
        type=int,
        default=8,
        help=(
            "Target number of Spark partitions before Presidio mapPartitions "
            "(higher spreads work across more executors). Use 0 to keep the "
            "DataFrame's natural partitioning."
        ),
    )
    args = parser.parse_args()

    logger.info(
        f"m=main,msg='starting job',environment={args.environment},"
        f"datalake_bucket={args.datalake_bucket},schema={args.schema},"
        f"table_name={args.table_name}"
    )

    return args


def get_sample(spark: SparkSession, date_filter: str) -> DataFrame:
    """
    Get a sample of the data from the specified layer from the sampling table
    generated by the sampling DAG.

    Args:
        date_filter (str): The execution date to get the sample from.

    Returns:
        DataFrame: A DataFrame containing the sample data.
    """
    logger.info("m=get_sample,msg='getting sample data'")
    execution_date = datetime.strptime(date_filter, "%Y-%m-%d")
    year = execution_date.year
    month = execution_date.month
    day = execution_date.day
    query = f"""
        SELECT
          layer,
          id_entity,
          database_name,
          table_name,
          column_name,
          sample,
          length(to_json(sample)) AS len_sample,
          ARRAY_AGG(column_name) AS list_column_name,
          {year} AS year,
          {month} AS month,
          {day} AS day
        FROM
          datalake_anonymization.columns_sample_data
        WHERE
          ts_ingested = MAKE_DATE({year}, {month}, {day})
          and status = 'SUCCESS'
        GROUP BY ALL
      """
    return spark.sql(query)


def main():
    """
    Main function to load PII scan results into the datalake.

    //TODO: Move DF transformations from main function.
    """
    logger.info("m=main,msg='Starting PII scan load into the datalake'")
    args = parse_args()
    partition_cols = ast.literal_eval(args.partitions)
    max_workers = args.max_workers
    config_service = ConfigurationService(args.source)
    recognizer_dict_list = config_service.get_config("recognizers")

    spark = SparkSession.getActiveSession() or SparkSession.builder.getOrCreate()

    output_schema = StructType(
        [
            StructField("layer", StringType(), True),
            StructField("id_entity", StringType(), True),
            StructField("database_name", StringType(), True),
            StructField("table_name", StringType(), True),
            StructField("column_name", StringType(), True),
            StructField("sample", ArrayType(StringType()), True),
            StructField("len_sample", IntegerType(), True),
            StructField("list_column_name", ArrayType(StringType()), True),
            StructField("year", IntegerType(), True),
            StructField("month", IntegerType(), True),
            StructField("day", IntegerType(), True),
            StructField(
                "sample_results",
                ArrayType(
                    ArrayType(MapType(StringType(), StringType(), True), True), True
                ),
                True,
            ),
            StructField(
                "col_results",
                ArrayType(
                    ArrayType(MapType(StringType(), StringType(), True), True), True
                ),
                True,
            ),
        ]
    )

    df = get_sample(spark, date_filter=args.load_start_date)
    if max_workers > 0:
        df = df.repartition(max_workers)
        logger.info(
            f"m=main,msg='repartitioned for Presidio',target_partitions={max_workers}"
        )

    rdd = df.rdd.mapPartitions(make_process_partition(recognizer_dict_list))
    df_rebuilt = spark.createDataFrame(data=rdd, schema=output_schema).cache()

    df_explode_sample = (
        df_rebuilt.select(
            "layer",
            "id_entity",
            "database_name",
            "table_name",
            "column_name",
            "sample_results",
            "year",
            "month",
            "day",
        )
        .withColumn(
            "sample_results_exploded",
            explode(col("sample_results").alias("sample_results_exploded")),
        )
        .withColumn(
            "sample_results_exploded_inner",
            explode(
                col("sample_results_exploded").alias("sample_results_exploded_inner")
            ),
        )
        .withColumn("sample_results_json", to_json(col("sample_results")))
        .select(
            "layer",
            "id_entity",
            "database_name",
            "table_name",
            "column_name",
            "sample_results_json",
            col("sample_results_exploded_inner.matched_value").alias(
                "sample_matched_value"
            ),
            col("sample_results_exploded_inner.type").alias("type"),
            col("sample_results_exploded_inner.score").alias("score"),
            "year",
            "month",
            "day",
        )
    )
    grouped_sample = df_explode_sample.groupBy(
        "layer",
        "id_entity",
        "database_name",
        "table_name",
        "column_name",
        "sample_results_json",
        "year",
        "month",
        "day",
        "type",
    ).agg(count("*").alias("count"))

    summary_sample = grouped_sample.groupBy(
        "layer",
        "id_entity",
        "database_name",
        "table_name",
        "column_name",
        "sample_results_json",
        "year",
        "month",
        "day",
    ).agg(collect_list(struct("type", "count")).alias("sample_summary"))

    df_explode_col = (
        df_rebuilt.select(
            "layer",
            "id_entity",
            "database_name",
            "table_name",
            "column_name",
            "col_results",
            "year",
            "month",
            "day",
        )
        .withColumn(
            "col_results_exploded",
            explode(col("col_results").alias("col_results_exploded")),
        )
        .withColumn(
            "col_results_exploded_inner",
            explode(col("col_results_exploded").alias("col_results_exploded_inner")),
        )
        .withColumn("col_results_json", to_json(col("col_results")))
        .select(
            "layer",
            "id_entity",
            "database_name",
            "table_name",
            "column_name",
            "col_results_json",
            col("col_results_exploded_inner.matched_value").alias("col_matched_value"),
            col("col_results_exploded_inner.type").alias("type"),
            col("col_results_exploded_inner.score").alias("score"),
            "year",
            "month",
            "day",
        )
    )
    grouped_col = df_explode_col.groupBy(
        "layer",
        "id_entity",
        "database_name",
        "table_name",
        "column_name",
        "col_results_json",
        "year",
        "month",
        "day",
        "type",
    ).agg(count("*").alias("count"))

    summary_col = grouped_col.groupBy(
        "layer",
        "id_entity",
        "database_name",
        "table_name",
        "column_name",
        "col_results_json",
        "year",
        "month",
        "day",
    ).agg(collect_list(struct("type", "count")).alias("col_summary"))
    final_df = summary_sample.join(
        summary_col,
        on=[
            "layer",
            "id_entity",
            "database_name",
            "table_name",
            "column_name",
            "year",
            "month",
            "day",
        ],
        how="inner",
    )

    load_table(
        final_df,
        args.environment,
        args.datalake_bucket,
        args.schema,
        args.table_name,
        partition_cols,
    )


if __name__ == "__main__":
    main()
