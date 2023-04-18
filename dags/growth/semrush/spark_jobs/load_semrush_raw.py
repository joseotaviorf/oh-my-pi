import requests
from datetime import datetime
from dateutil.relativedelta import relativedelta
from pyspark.sql.functions import lit
from functools import reduce
from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.formatters import StringFormatter
from argparse import ArgumentParser
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.db import DatalakeMetastoreService


## Logger
JOB_NAME = "load_semrush_raw"
logger = QuintoAndarLogger(JOB_NAME)


## API Key
DATABRICKS_SCOPE = "quintoandar"
base_dbutils = BaseDBUtils()
if base_dbutils.get_dbutils() is not None:
    dbutils = base_dbutils.get_dbutils()
api_key = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.SEMRUSH)


## Spark Client
spark_client = SparkClient()


## Spark Job
if __name__ == "__main__":

    ## Parser
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("table_name")
    parser.add_argument("execution_date")
    

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.env}, source={args.source}, datalake_bucket={args.datalake_bucket}
            table_name={args.table_name}, execution_date={args.execution_date}.
            msg=print spark jobs args
        """
    )


    ## Args
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date = args.execution_date
    
        
    ## Config Service
    config_service = ConfigurationService(source)
    report_list = config_service.get_config("report_list")
    raw_partition_cols = config_service.get_config("raw_partition_cols")


    ## Loaders and Services
    s3_loader = S3Loader()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)


    ## Creating database
    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)


    ## API get
    endpoint = f'https://api.semrush.com/?key={api_key}'
    report_body = report_list[table_name]
    report_configs = report_body['configs']
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    if report_body['display_limit']: # Only returning limited data

        params = '&' + '&'.join([f"{config}={report_configs[config]}" for config in report_configs])
        dfs = []
        startRow = 0
        endRow = report_body['display_limit']
        maxRows = 100000

        for i in range(startRow, endRow, maxRows): #Limiting rows per call
            offset = i
            limit = min(i + maxRows - 1, endRow)
            display_offset = f'&display_offset={offset}'
            display_limit = f'&display_limit={limit}'
            APIUnitsBalance = int(requests.get(f'http://www.semrush.com/users/countapiunits.html?key={api_key}').text)
            APIUnitsNeeded = limit*10

            if APIUnitsBalance >= APIUnitsNeeded: # Check API units Balance
                url_request = endpoint + params + display_offset + display_limit
                response = requests.get(url_request)
                if response.status_code == 200:
                    request_text = response.text
                    
                    if request_text:
                        csvData = sc.parallelize(request_text.split('\r\n'))
                        df_semrush = spark.read\
                        .option("inferSchema",False)\
                        .option("header", "true")\
                        .option("mode","FAILFAST")\
                        .option("delimiter",";")\
                        .csv(csvData)\
                        .withColumn("date", lit(execution_date))

                        df_semrush = (
                            SparkDataFrameService(df_semrush)
                            .format_column_names()
                            .create_year_month_day_columns_from_date(dt_execution)
                            .output()
                        )

                        dfs.append(df_semrush)

                        logger.info(
                        f"""
                        m=Successfully extracted data for {url_request}.
                        API Units balance before={APIUnitsBalance}
                        API Units balance after={APIUnitsBalance-APIUnitsNeeded}
                        """
                        )

                else:
                    raise Exception(
                        f"""
                        m=Failed to extract data for {url_request}.
                        Status code={response.status_code}.
                        """
                    )
            else:
                raise Exception(
                    f"""
                    m=Not enough API Units.
                    balance={APIUnitsBalance}, needed={APIUnitsNeeded}
                    """
                )

        ## Loader
        if dfs:
            df = reduce(DataFrame.unionAll, dfs)

            s3_loader.load_df(
                df=df,
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                s3_path=f"{database_location}{table_name}",
                partitions=raw_partition_cols,
                compression="gzip"
            )

            spark_metastore_loader.update_metastore(
                df=df,
                database_name=database_name,
                table_name=table_name,
                format_options=SparkTableStorageFormat.DEFAULT_RAW,
                database_location=database_location,
                partitions=raw_partition_cols,
                force_recreate=True,
            )

            spark_metastore_service.create_new_partitions_from_df(
                df=df,
                database_name=database_name,
                table_name=table_name,
                partition_cols=raw_partition_cols,
            )
            logger.info(
                f"""
                m=Successfully save data of {table_name} table.
                """
            )
        else:
            logger.info(
                f"""
                m=df empty for {table_name} table on date {dt_execution}.
                """
            )

    else:
        raise Exception(
            f"""
            m=Failed to extract data.
            No rows limit for {table_name}.
            """
        )