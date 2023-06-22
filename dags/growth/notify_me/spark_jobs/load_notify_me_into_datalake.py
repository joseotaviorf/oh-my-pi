import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatabaseEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat, SparkDataFrameService
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import PostgresConsumer
from bietlejuice.pipeline import FullTableLoaderPipeline
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders import SparkMetastoreLoader

JOB_NAME = "load_notify_me_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    return parser.parse_args()


def get_conn_config():
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    conn_config_json = dbutils.secrets.get(
        scope="quintoandar", key=DatabaseEnum.NOTIFY_ME
    )

    return json.loads(conn_config_json)


def get_table_config(table_name, table_configs):
    if table_name not in table_configs:
        unixtime_measure = None
        is_incremental = True
        date_filter_column = "updated_at"
    else:
        unixtime_measure = table_configs[table_name].get("unixtime_measure")
        is_incremental = (
            table_configs[table_name].get("extraction_type") == "incremental"
        )
        date_filter_column = table_configs[table_name].get(
            "date_filter_column", "updated_at"
        )

    return unixtime_measure, is_incremental, date_filter_column


def main():
    args = parse_arguments()
    environment = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date

    config_service = ConfigurationService(source)
    partition_cols = config_service.get_config("partition_cols")

    logger.info(
        f"""
        m=__main__, environment={environment}, source={source}, datalake_bucket={datalake_bucket},
        execution interval is between start date {load_start_date} and {load_end_date}, msg=Starting spark job...
        """
    )

    conn_config = get_conn_config()

    spark_client = SparkClient()

    postgres_consumer = PostgresConsumer(conn_config, spark_client)
    s3_loader = S3Loader()

    format_options = SparkTableStorageFormat.DEFAULT_RAW

    tables = postgres_consumer.get_table_names_and_sizes().collect()
    table_configs = config_service.get_config("tables")

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    logger.info("m=__main__, msg=Creating database in Spark Metastore if not exists...")
    spark_metastore_service.create_database(database_name)

    unixtime_measure, is_incremental, date_filter_column = get_table_config(
        table_name, table_configs
    )
    
    if is_incremental:
        query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
                source, 
                table_name, 
                "raw"
        ).format(load_start_date=load_start_date,load_end_date=load_end_date)        

        df = postgres_consumer.get_data_from_query(query)
            
        df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("dt")
                .output()
        )    

        # load data into datalake
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
            compression="gzip",
        )

        spark_metastore_loader.update_metastore(
            df,
            database_name,
            table_name,
            format_options,
            database_location,
            partition_cols,
        )
        
        spark_metastore_service.create_new_partitions_from_df(
        df=df,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partition_cols,
        )

    else:
        df = postgres_consumer.get_data_from_table(table_name)
        FullTableLoaderPipeline(
            database_name, table_name, database_location, LayerEnum.RAW, None
        ).load_and_register(df, format_options)


if __name__ == "__main__":
    main()
