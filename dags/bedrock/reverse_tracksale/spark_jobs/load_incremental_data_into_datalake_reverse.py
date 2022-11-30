import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta

from pyspark.sql.functions import when, count, lit, col
from pyspark.sql.window import Window as w
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_incremental_data_into_datalake_reverse"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="source name")
    parser.add_argument("campaign_query", help="query ")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    campaign_query = args.campaign_query
    execution_date = args.execution_date
    partition_cols = ["year", "month", "day"]

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket}, source={source},
        campaign_query={campaign_query}, execution_date={execution_date}, partition_cols={partition_cols},
        msg=Starting Spark Job..."""
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)
    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=f"reverse_{source}",
        layer=LayerEnum.REVERSE.value,
        table_name=campaign_query,
    )

    # We need to drop the duplicates here the first time, because some queries might return duplicates.
    # Otherwise, is_dispatched will be True even if we have never sent them the email before.
    df = spark_client.get_records(query).dropDuplicates(["customer_name", "customer_email"])

    execution_date = datetime.strptime(execution_date, "%Y-%m-%d") + timedelta(days=1)

    path = f"{datalake_bucket}/{campaign_query}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}/"

    try:
        df = df.unionByName(
            s3_consumer.get_data_from_file(path=path, format="parquet"),
            allowMissingColumns=True,
        )
    except Exception as e:
        logger.error("m=There's no data here yet, message_error={}".format(e))

    df = df.withColumn(
        "is_dispatched",
        when(
            count("customer_email").over(
                w.partitionBy("customer_name", "customer_email")
            )
            > 1,
            True,
        ).otherwise(False),
    ).dropDuplicates(["customer_name", "customer_email"])

    df = (
        df.select(df["*"])
        .where(col("customer_email").isNotNull())
        .withColumn("column_create_date", lit(execution_date))
    )

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("column_create_date")
        .output()
    )

    s3_data_path = datalake_bucket
    db_info = DatalakeMetastoreService.get_db_info(environment, source, s3_data_path)
    metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(metastore_service)
    s3_loader = S3Loader()

    table_name = campaign_query
    database_name = f"datalake_{source}_reverse"
    format_options = SparkTableStorageFormat.DEFAULT_DW
    database_location = s3_data_path

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    metastore_service.create_database(database_name)

    s3_loader.load_df(
        df=df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
    )

    spark_metastore_loader.update_metastore(
        df, database_name, table_name, format_options, database_location
    )
