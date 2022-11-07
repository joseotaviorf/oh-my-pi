import json

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService, QUERIES_DATALAKE_PATH
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.services import FileService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.pipeline import LayerEnum

logger = QuintoAndarLogger("create_clean_emlio_incremental_table_in_datalake")

parser = ArgumentParser(description="create_clean_emlio_incremental_table_in_datalake")
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("table_name")
parser.add_argument("partitions")

if __name__ == "__main__":

    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    partition_cols = json.loads(args.partitions)

    logger.info(
        "m=__main__, date={}, source={}, table_name={}, msg=Emlio clean job started".format(
            execution_date, source, table_name
        )
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    query = """select 
                uuid,
                service_id as id_service,
                service_version,
                inference_type,
                service_type,
                timestamp(log_timestamp) as ts_log,
                inputs,
                outputs,
                keys as service_keys,
                year,
                month,
                day
                from 
                datalake_emlio_raw.{table_name}
                where year={year} AND month={month} AND day={day}""".format(table_name=table_name, year=year, month=month, day=day)

    df = spark_client.get_records(query)

    database_name = db_info["db_clean_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_CLEAN
    database_location = db_info["db_clean_path"]

    s3_path = database_location + table_name
    df_writer = (
        df.write.mode("overwrite")
        .format(format_options)
        .option("maxRecordsPerFile", 2000000)
        .partitionBy(*partition_cols)
    )
    df_writer.save(path=s3_path)

    logger.info(
        "m=load_incremental_table, path={}, "
        "partitions={}, msg=loaded partitions successfully".format(
            s3_path, partition_cols
        )
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=df,
        database_name=database_name,
        table_name=table_name,
        format_options=format_options,
        database_location=database_location,
        partitions=partition_cols,
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partition_cols,
    )

    spark_metastore_service.refresh_table(database_name, table_name)