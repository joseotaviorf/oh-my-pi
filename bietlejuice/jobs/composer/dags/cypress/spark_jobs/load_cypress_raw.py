from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.spark import SparkTableStorageFormat
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.services.configuration_service import (
    ConfigurationService,
)

from pyspark.sql.utils import AnalysisException

JOB_NAME = "load_cypress_raw"
PATH_ERR = "Path does not"

logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")

    args = parser.parse_args()
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date = args.execution_date

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    schema = config_service.get_config("schema")
    cypress_source_bucket = config_service.get_config("cypress_source_bucket")
    cypress_enrich_query = config_service.get_config("cypress_enrich_query")[table_name]

    logger.info(
        f"""m=__main__, environment={env}, datalake_bucket={datalake_bucket}, source={source},
        table_name={table_name}, execution_date={execution_date}, msg=Starting spark job..."""
    )

    spark_client = SparkClient()

    # Only handle
    try:
        df = (
            spark_client.conn.read.schema(schema)
            .option("multiLine", True)
            .option("mode", "PERMISSIVE")
            .json(f"s3://{cypress_source_bucket}/*/{execution_date}/*/*.json")
        )
    except AnalysisException as e:
        if str(e).find(PATH_ERR) != -1:
            logger.warning(
                f"m=__main__, msg={str(e)}. The load of {execution_date} will be skipped."
            )
        else:
            logger.error(f"m=__main__, msg={str(e)}.")
    else:

        # TODO: the following enrich transformations must be removed and applied in a enrich DAG
        # [START] enrich transformations
        df.createOrReplaceTempView(f"temp_view_{source}_{table_name}")
        df_enrich = spark_client.conn.sql(
            cypress_enrich_query.format(source=source, table_name=table_name)
        )
        # [END] enrich transformations

        if not df_enrich.rdd.isEmpty():
            db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
            database_name = db_info["db_raw_databricks"]
            database_location = db_info["db_raw_path"]

            format_options = SparkTableStorageFormat.DEFAULT_RAW

            s3_loader = S3Loader()
            s3_loader.load_df(
                df=df_enrich,
                s3_path=f"{database_location}{table_name}",
                format_options=format_options,
                partitions=raw_partition_cols,
            )

            spark_metastore_service = SparkMetastoreService(spark_client)
            spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
            spark_metastore_loader.update_metastore(
                df=df_enrich,
                database_name=database_name,
                table_name=table_name,
                format_options=format_options,
                database_location=database_location,
                partitions=raw_partition_cols,
                force_recreate=False,
            )

            spark_metastore_service.create_new_partitions_from_df(
                df=df_enrich,
                database_name=database_name,
                table_name=table_name,
                partition_cols=raw_partition_cols,
            )
