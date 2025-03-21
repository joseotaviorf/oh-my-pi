import argparse
import ast
import json
from datetime import datetime
from typing import Dict, Iterator

from presidio_analyzer.nlp_engine import NlpEngineProvider
from presidio_analyzer import (
    AnalyzerEngine,
    BatchAnalyzerEngine,
    DictAnalyzerResult,
    RecognizerRegistry,
)
from pyspark.sql import DataFrame
from pyspark.sql.functions import udf, from_json, col, explode_outer, explode, lit
from pyspark.sql.types import StructType, StringType, StructField, ArrayType, DoubleType

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.loaders.delta_loader import DeltaLoader

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_pii_scan_into_datalake"
logger = QuintoAndarLogger(JOB_NAME)

RECOGNIZERS_PATH = "prod_conf.yml"
SCORE_THRESHOLD = 0.6

ENTITIES_LIST = [
    "BRAZIL_RG",  # Custom entity
    "BRAZIL_CPF",  # Custom entity
    "LOCATION",  # Custom entity
    "CREDIT_CARD",
    "EMAIL_ADDRESS",
    "IP_ADDRESS",
    "LOCATION",
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

def load_recognizers_from_yaml() -> RecognizerRegistry:
    """
    Load custom recognizers from a YAML configuration file and add them to the registry.

    Returns:
        registry: A RecognizerRegistry instance with the custom recognizers loaded.
    """
    registry = RecognizerRegistry()
    registry.load_predefined_recognizers()
    registry.add_recognizers_from_yaml(RECOGNIZERS_PATH)

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

def build_batch_analyzer() -> BatchAnalyzerEngine:
    """
    Build and return a BatchAnalyzerEngine instance.

    Returns:
        BatchAnalyzerEngine: An instance of BatchAnalyzerEngine configured with the custom recognizers and NLP engine.
    """
    nlp_config = load_nlp_config()
    registry = load_recognizers_from_yaml()
    provider = NlpEngineProvider(nlp_configuration=nlp_config)

    nlp_engine = provider.create_engine()

    analyzer = AnalyzerEngine(nlp_engine=nlp_engine, registry=registry)
    batch_analyzer = BatchAnalyzerEngine(analyzer_engine=analyzer)

    return batch_analyzer

def analyze(df_dict, is_column_name=False) -> Iterator[DictAnalyzerResult]:
    """
    Analyze a dictionary of data for PII entities.

    Args:
        df_dict (dict): The input dictionary containing data to be analyzed.
        is_column_name (bool): Flag indicating whether to use column name entities for analysis.

    Returns:
        Iterator[DictAnalyzerResult]: A list of detected PII entities.
    """
    analyzer = build_batch_analyzer()
    entities_list = ENTITIES_LIST
    if is_column_name:
        entities_list = COLUMN_NAME_ENTITIES

    return analyzer.analyze_dict(
        input_dict=df_dict,
        entities=entities_list,
        score_threshold=SCORE_THRESHOLD,
        language="en",
    )

def analyze_udf(column_name: str, sample: list, is_column_name=False) -> str:
  dict_to_analyze = {
    column_name: sample
  }
  analyzer_results = list(analyze(dict_to_analyze, is_column_name=is_column_name))
  row = []
  for index, value in enumerate(analyzer_results[0].value):
    row.append({
        "value": str(value),
        "recognizer_results": []
    })
    results = analyzer_results[0].recognizer_results[index]
    if not results:
      row[index]["recognizer_results"].append({"type": "NOT_FOUND", "score": 0.0})
    for item in results:
      row[index]["recognizer_results"].append({"type": item.entity_type, "score": str(item.score)})
  return json.dumps(row)

def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
    partition_cols: list
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
        partition_by=partition_cols
    )

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("schema", help="name of the schema of the table to be saved in the data lake")
    parser.add_argument("table_name", help="name of the table to be saved in the data lake")
    parser.add_argument("load_start_date", help="timestamp of the ingest to get the sample from")
    parser.add_argument("partitions", type=str)
    args = parser.parse_args()

    logger.info(f"m=main,msg='starting job',environment={args.environment},"
                f"datalake_bucket={args.datalake_bucket},schema={args.schema},"
                f"table_name={args.table_name}"
    )

    return args

def get_sample(date_filter) -> DataFrame:
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
          ARRAY_AGG(column_name) AS list_column_name,
          {year} AS year,
          {month} AS month,
          {day} AS day
        FROM
          datalake_anonymization.columns_sample_data
        WHERE
          MAKE_DATE(year, month, day) = '{date_filter}'
        GROUP BY ALL
        LIMIT 10
      """
    return spark.sql(query)

def main():
    """
    Main function to load PII scan results into the datalake.
    """
    logger.info("m=main,msg='Starting PII scan load into the datalake'")
    args = parse_args()
    partition_cols = ast.literal_eval(args.partitions)

    object_schema = StructType([
        StructField("type", StringType(), True),
        StructField("score", DoubleType(), True)
    ])

    recognizer_schema = ArrayType(StructType([
        StructField("value", StringType(), True),
        StructField("recognizer_results", ArrayType(object_schema), True)
    ]), True)

    udf_analyzer = udf(analyze_udf)
    df = get_sample(date_filter= args.load_start_date)

    df_analysis = (
        df
        .withColumn("analysis", udf_analyzer(df["column_name"], df["sample"]))
        .withColumn("column_name_analysis", udf_analyzer(df["column_name"], df["list_column_name"], lit(True)))
        .withColumn("analysis_parsed", from_json(
            col("analysis"),
            recognizer_schema
        ))
        .withColumn("column_analysis_parsed", from_json(
            col("column_name_analysis"),
            recognizer_schema
        ))
    )

    df_explode = (
        df_analysis
        .select(
            "layer",
            "id_entity",
            "database_name",
            "table_name",
            "column_name",
            "analysis_parsed",
            "column_analysis_parsed",
            "year",
            "month",
            "day"
        )
        .withColumn("analysis_exploded", explode(col("analysis_parsed").alias("analysis_exploded")))
        .withColumn("column_analysis_exploded",
                    explode(col("column_analysis_parsed").alias("column_analysis_exploded")))
        .withColumn("parsed_value", col("analysis_exploded.value").alias("value"))
        .withColumn("recognizer_results",
                    explode_outer(col("analysis_exploded.recognizer_results")).alias("recognizer_results"))
        .withColumn("column_parsed_value", col("column_analysis_exploded.value").alias("column_value"))
        .withColumn("column_recognizer_results",
                    explode_outer(col("column_analysis_exploded.recognizer_results")).alias(
                        "column_recognizer_results"))
        .select(
            "layer",
            "id_entity",
            "database_name",
            "table_name",
            "column_name",
            "parsed_value",
            col("recognizer_results.type").alias("type"),
            col("recognizer_results.score").alias("score"),
            col("column_recognizer_results.type").alias("column_type"),
            col("column_recognizer_results.score").alias("column_score"),
            "year",
            "month",
            "day"
        )
    )
    load_table(
        df_explode,
        args.environment,
        args.datalake_bucket,
        args.schema,
        args.table_name,
        partition_cols
    )
if __name__ == "__main__":
    main()
