import logging
import json
from argparse import ArgumentParser
from datetime import datetime

from pyspark.sql.functions import col, udf, concat, lit

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader, S3Loader
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.base.pipeline import LayerEnum

JOB_NAME = "facebook_insights_load_table_to_enrich"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def map_account_id_to_name(account_id):
    return accounts_name_mapping[str(account_id)]


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument("target_database_base_name")
    parser.add_argument("table_name", type=str, help="table name that will be created")
    parser.add_argument("partitions")
    parser.add_argument(
        "accounts_name_mapping",
        type=str,
        help="mapping from account_id to account_name",
    )
    parser.add_argument("execution_date")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    database_base_name = args.database_base_name
    table_name = args.table_name
    execution_date = args.execution_date
    target_database_base_name = args.target_database_base_name
    partitions = json.loads(args.partitions.replace("'", '"'))
    accounts_name_mapping = json.loads(args.accounts_name_mapping.replace("'", '"'))

    logger.info(
        f"""
                m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, layer={LayerEnum.ENRICH},
                database_base_name={database_base_name}, table_name={table_name},  msg=Job execution started
        """
    )

    dt_datetime = datetime.strptime(execution_date, "%Y-%m-%d")
    dt_dict = dict(
        [
            ("year", dt_datetime.year),
            ("month", dt_datetime.month),
            ("day", dt_datetime.day),
        ]
    )

    (
        database_clean_name,
        database_location,
        athena_database_name,
    ) = DatalakeMetastoreService.get_layer_info(
        env, database_base_name, datalake_bucket, LayerEnum.CLEAN.value
    )

    (
        target_database_name,
        target_database_location,
        target_athena_database_name,
    ) = DatalakeMetastoreService.get_layer_info(
        env, target_database_base_name, datalake_bucket, LayerEnum.ENRICH.value
    )

    spark_client = SparkClient()
    spark_session = spark_client.conn

    map_account_id_to_name_udf = udf(map_account_id_to_name)

    df = spark_session.table(f"{database_clean_name}.{table_name}")

    df = df.where("year={year} and month={month} and day={day}".format(**dt_dict))

    sk_ad = concat(col("id_ad"), lit("{year}-{month}-{day}"))

    df = (
        df.withColumn("acc", map_account_id_to_name_udf(col("id_account")))
        .withColumn("is_test_campaign", col("acc").like("ZEBRA%"))
        .withColumn("sk_ad", sk_ad)
    )

    spark_metastore_service = SparkMetastoreService(spark_client)
    s3_loader = S3Loader()

    format_options = SparkTableStorageFormat.get_storage(LayerEnum.ENRICH.value)

    s3_loader.load_df(
        df=df,
        format_options=format_options,
        s3_path=target_database_location + table_name,
        partitions=partitions,
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=target_database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=target_database_location,
        partitions=partitions,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=target_database_name,
        table_name=table_name,
        partition_cols=partitions,
    )

    spark_metastore_service.refresh_table(target_database_name, table_name)
