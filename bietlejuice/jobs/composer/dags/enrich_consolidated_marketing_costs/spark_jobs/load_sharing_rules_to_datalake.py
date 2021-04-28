import json
import logging

from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatabaseEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat

JOB_NAME = "load_sharing_rules_to_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

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

    target = "consolidated_marketing_costs"
    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_session = spark_client.conn
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    redshift_conn = json.loads(dbutils.secrets.get("quintoandar", DatabaseEnum.DW))
    source_schema = "staging"
    table_name = "sharing_rules_marketing_daily_costs"

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

    df = (
        spark_session.read.format("com.databricks.spark.redshift")
        .option("url", url)
        .option("dbtable", f"{source_schema}.{table_name}")
        .option("tempdir", f"s3n://{datalake_bucket}/redshift_tempdir/")
        .option("forward_spark_s3_credentials", True)
        .load()
    )

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, target, datalake_bucket
    )

    database_location = datalake_info["db_enrich_path"]
    format_options = SparkTableStorageFormat.DEFAULT_ENRICH
    database_name = datalake_info["db_enrich_databricks"]

    s3_loader.load_df(
        df=df,
        s3_path=database_location + table_name,
        format_options=format_options,
        write_mode="overwrite",
    )

    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
    )
