from argparse import ArgumentParser, Namespace
from typing import List, Dict, Tuple
from pyspark.sql.functions import lit, coalesce, when, lower, udf, col
from pyspark.sql.types import BooleanType
from pyspark.sql import DataFrame
import ftfy

from bietlejuice.base.udfs.udf_enum import UDFEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_description_features"

def main():
    args = parse_args()
    patterns_by_country_code, fields = read_configs(args)
    descriptions_df = prepare_descriptions_dataframe(fields)
    descriptions_df = infer_features_from_description(descriptions_df, patterns_by_country_code)
    save_df(descriptions_df, args)

def parse_args() -> Namespace:
    """Parse arguments passed to the job, which are the same as the ones from load_table_full.py"""

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument(
        "relative_query_path",
        type=str,
        help="relative query path for sql file to create table",
    )
    parser.add_argument("table_name", type=str, help="table name that will be created")

    return parser.parse_args()

def read_configs(args: Namespace) -> Tuple[Dict[str, List], List[str]]:
    """Read patterns_by_country_code and fields from config file, returning both as a tuple"""

    config_service = ConfigurationService(args.relative_query_path)
    patterns_by_country_code = config_service.get_config("patterns_by_country_code")
    fields = config_service.get_config("fields")
    return patterns_by_country_code, fields

def prepare_descriptions_dataframe(fields: List[str]) -> DataFrame:
    """Returns a dataframe with all descriptions and fields to be inferred, with null values"""

    descriptions_df = get_raw_descriptions_dataframe()
    clean_descriptions_df = clean_description(descriptions_df)
    clean_descriptions_with_fields_df = add_all_fields(clean_descriptions_df, fields)
    return clean_descriptions_with_fields_df

def get_raw_descriptions_dataframe() -> DataFrame:
    """Returns a dataframe with all descriptions from house, or from lead_3p if it is a third party house"""

    return spark.sql("""
        SELECT
            h.id AS id_house,
            COALESCE(NULLIF(TRIM(l.house_description), ''), h.house_description) AS house_description,
            ch.country_code
        FROM
            datalake_ebdb_clean.house AS h
        JOIN
            datalake_ebdb_country.house AS ch
                ON h.id = ch.id_house
        LEFT JOIN
            datalake_brokers_supply_processor.lead_3p AS l
                ON h.id_external = l.uuid_lead
        WHERE
            NULLIF(TRIM(h.house_description), '') IS NOT NULL
            OR NULLIF(TRIM(l.house_description), '') IS NOT NULL
    """)

def clean_description(descriptions_df: DataFrame) -> DataFrame:
    """Returns a dataframe with all descriptions cleaned, removing accentuation and lowercasing"""

    # Used to fix encoding problems, particularly from lead_3p
    # e.g., prÃ³ximo Ã  praÃ§a -> próximo à praça
    fix_encoding_issues = udf(ftfy.fix_text)
    remove_accentuation = udf(UDFEnum.get_udf(udf_identifier='SF_REMOVE_ACCENTUATION'))
    return descriptions_df.withColumn(
        'house_description',
        remove_accentuation(lower(fix_encoding_issues(col('house_description'))))
    )

def add_all_fields(descriptions_df: DataFrame, fields: List[str]) -> DataFrame:
    """Returns a dataframe with all fields to be inferred, with null values"""

    for field in fields:
        descriptions_df = descriptions_df.withColumn(field, lit(None).cast(BooleanType()))
    return descriptions_df

def infer_features_from_description(descriptions_df, patterns_by_country_code: Dict[str, List[Tuple[str, str, bool]]]) -> DataFrame:
    """Returns a dataframe with all fields inferred from description, using regex"""

    for country_code, regex_list in patterns_by_country_code.items():
        for description_pattern in regex_list:
            descriptions_df = descriptions_df.withColumn(
                description_pattern['field'],
                coalesce(
                    col(description_pattern['field']),
                    when(
                        (col('country_code') == lit(country_code)) & col('house_description').rlike(description_pattern['pattern']), lit(description_pattern['output'])
                    )
                )
            )
    return descriptions_df

def save_df(df: DataFrame, args: Namespace) -> None:
    """Saves dataframe to enrich layer"""

    spark_client = SparkClient()
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(args.env, args.database_base_name, args.datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]
    spark_metastore_service.create_database(database_name)

    s3_loader.load_df(
        df=df,
        format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
        s3_path=f"{database_location}{args.table_name}",
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=args.table_name,
        format_options=SparkTableStorageFormat.DEFAULT_ENRICH,
        database_location=database_location,
    )

if __name__ == '__main__':
    main()