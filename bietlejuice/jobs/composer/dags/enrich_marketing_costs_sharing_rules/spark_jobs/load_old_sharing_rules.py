from bietlejuice.jobs.composer.services.file_service import FileService
import json
import logging

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum, QUERIES_DATALAKE_PATH
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

from pyspark.sql.functions import lit

JOB_NAME = "load_sharing_rules_to_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_df_from_redshift(query_path):
    rule_name_raw = query_path.split("/")[-1]
    rule_name = FileService.remove_file_extension(rule_name_raw)

    rule_query = FileService.get_query_from_file_name(query_path)

    df = (
        spark_session.read.format("com.databricks.spark.redshift")
        .option("url", url)
        .option("query", rule_query)
        .option("tempdir", f"s3n://{datalake_bucket}/redshift_tempdir/")
        .option("forward_spark_s3_credentials", True)
        .load()
    )

    df = df.withColumn("id_rule", lit(rule_name))

    return df


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.environment},
            datalake_bucket={args.datalake_bucket}, msg=print spark jobs args"
        """
    )

    layer = LayerEnum.ENRICH
    table_name = "old_sharing_rules"
    target = "marketing_costs_sharing_rules"
    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_session = spark_client.conn
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    redshift_conn = json.loads(dbutils.secrets.get("quintoandar", DatabaseEnum.DW))

    host = redshift_conn["host"]
    port = redshift_conn["port"]
    db = redshift_conn["db"]
    user = redshift_conn["user"]
    pwd = redshift_conn["pwd"]

    url = (
        f"jdbc:redshift://{host}:{port}/{db}?"
        "ssl=true&sslfactory=com.amazon.redshift.ssl.NonValidatingFactory&"
        f"user={user}&password={pwd}"
    )

    rule_path = f"{QUERIES_DATALAKE_PATH}{target}/old_sharing_rules/{layer.value}"

    try:
        sql_file_list_raw = FileService.list_files(rule_path)
        nbr_files = len(sql_file_list_raw)

    except (RuntimeError):
        nbr_files = 0
        logger.info(
            f"m={JOB_NAME}, msg=no rules in old_sharing_rules, skipping session"
        )

    if nbr_files > 0:

        sql_file_list_paths = [
            f"{rule_path}/{file_name}" for file_name in sql_file_list_raw
        ]

        for query_path in sql_file_list_paths:

            df = get_df_from_redshift(query_path)
            try:
                union_df = union_df.unionAll(df)
            except (NameError):
                union_df = df

        datalake_info = DatalakeMetastoreService.get_db_info(
            environment, target, datalake_bucket
        )

        database_location = datalake_info["db_enrich_path"]
        format_options = SparkTableStorageFormat.DEFAULT_ENRICH
        database_name = datalake_info["db_enrich_databricks"]

        s3_loader.load_df(
            df=union_df,
            s3_path=database_location + table_name,
            format_options=format_options,
        )

        spark_metastore_loader.update_metastore(
            df=union_df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
        )
