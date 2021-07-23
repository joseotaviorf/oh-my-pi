from argparse import ArgumentParser
from pyspark.sql.functions import col, lit, udf

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.formatters import StringFormatter
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

JOB_NAME = "casa_mineira_google_ads_load_to_raw"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source", type=str, help="name of the source")
    parser.add_argument("report_type")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    report_type = args.report_type
    execution_date = args.execution_date
    config_service = ConfigurationService(source)

    ads_performance_bucket = config_service.get_config("ads_performance_bucket")[env]
    raw_partition_columns = config_service.get_config("raw_partition_columns")
    report_schemas = config_service.get_config("report_schemas")
    report_folder = config_service.get_config("report_folder_mapping")[report_type]
    report_account_regex_filter = config_service.get_config(
        "report_account_regex_filter"
    )

    logger.info(
        f"""m=__main__, environment={env}, source={source}, datalake_bucket={datalake_bucket},
        report_type={report_type}, execution_date={execution_date}, msg=Starting spark job..."""
    )

    spark_client = SparkClient()
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    df = (
        spark_client.conn.read.option("header", "true")
        .option(
            "basePath",
            f"s3://{ads_performance_bucket}/google-reports/report={report_folder}",
        )
        .csv(
            f"s3://{ads_performance_bucket}/google-reports/report={report_folder}/*/dt={execution_date}"
        )
        .filter(col("Account").rlike(report_account_regex_filter))
        .withColumn(
            "acc", udf(StringFormatter.set_alphanumeric_snake_case)(col("Account"))
        )
        .withColumn("raw_report_type", lit(report_folder))
        .toDF(*report_schemas[report_type])
    )

    s3_loader.load_df(
        df=df,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        s3_path=f"{database_location}{report_type}",
        partitions=raw_partition_columns,
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=report_type,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=database_location,
        partitions=raw_partition_columns,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=report_type,
        partition_cols=raw_partition_columns,
    )
