import json
import logging
import time
import ast
from argparse import ArgumentParser

from facebook_business.api import FacebookAdsApi
from facebook_business.adobjects.adaccount import AdAccount
from facebook_business.adobjects.adreportrun import AdReportRun
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.formatters import StringFormatter
from pyspark.sql.functions import udf

JOB_NAME = f"load_facebook_insights_region_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def save_to_datalake(
    dataframe,
    environment,
    source,
    datalake_bucket,
    table_name,
    partitions
):
    """
    Saves a Spark DataFrame to the data lake, creating the database structure,
    loading data to S3 and updating the metastore.
    
    Args:
        dataframe (pyspark.sql.DataFrame): Spark DataFrame containing the data to be saved
        environment (str): Execution environment
        source (str): Data source name
        datalake_bucket (str): S3 bucket name for the data lake
        table_name (str): Table name to be created in the metastore
        partitions (list): List of columns used for partitioning
    
    Returns:
        None
    """
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]

    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(
        df=dataframe,
        s3_path=f"{database_location}{table_name}",
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        partitions=partitions,
        compression="gzip",
    )

    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    spark_metastore_loader.update_metastore(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW,
        database_location=database_location,
        partitions=partitions,
        force_recreate=True,
    )

    spark_metastore_service.create_new_partitions_from_df(
        df=dataframe,
        database_name=database_name,
        table_name=table_name,
        partition_cols=partitions,
    )

def wait_for_job_completion(job_id, sleep_interval=5):
    """
    Waits for the completion of a Facebook Ads API asynchronous job, checking
    periodically the status until it completes or fails.
    
    Args:
        job_id (str): Facebook Ads API asynchronous job ID
        sleep_interval (int, optional): Interval in seconds between status checks. Default: 5
    
    Returns:
        bool: True if job completed successfully, False if it failed or an error occurred
    """
    async_job_run = AdReportRun(job_id)
    
    while True:
        try:
            async_job_run = async_job_run.api_get()
            
            status = async_job_run.get('async_status')
            completion = async_job_run.get('async_percent_completion')
            
            logger.info(f"Job Status: {status} ({completion}%)")
            
            if status == 'Job Completed':
                logger.info("Job Completed Successfully")
                return True
            elif status == 'Job Failed':
                logger.error("Job Failed")
                return False
            
            time.sleep(sleep_interval)
        
        except Exception as e:
            logger.error(f"Error checking job status: {e}")
            return False

def facebook_insights_request(account_id, table_name, start_date, end_date, breakdown):
    """
    Makes an asynchronous request to the Facebook Ads Insights API collecting ad performance data
    
    Args:
        account_id (str): Facebook ad account ID (without 'act_' prefix)
        table_name (str): Destination table name (used for logging)
        start_date (str): Start date in 'YYYY-MM-DD' format
        end_date (str): End date in 'YYYY-MM-DD' format
        breakdown (str): Type of breakdown to be applied (e.g., 'region')
    
    Returns:
        list: List of dictionaries containing Facebook insights data
    """

    base_dbutils = BaseDBUtils()
    dbutils = base_dbutils.get_dbutils()

    params = {
        'level': 'ad',
        'fields': [
            'account_id',
            'account_name',
            'ad_id',
            'ad_name',
            'adset_id',
            'adset_name',
            'campaign_id',
            'campaign_name',
            'reach',
            'impressions',
            'clicks',
            'actions',
            'date_start',
            'date_stop',
            'inline_link_clicks',
            'spend'
        ],
        'breakdowns': [ breakdown ],
        'time_increment': 1,
    'time_range': {
            'since': start_date, 
            'until': end_date, 
        }
    }

    configs = json.loads(dbutils.secrets.get(scope="quintoandar", key=APIEnum.FACEBOOK))

    FacebookAdsApi.init(access_token=configs['auth']['access_token'])

    account_instance = AdAccount(f'act_{account_id}')
    
    async_job = account_instance.get_insights(params=params, is_async=True)
    
    logger.info(f"Async job started. Job Id: {async_job['report_run_id']}")

    job_completed = wait_for_job_completion(async_job['report_run_id'])
    
    if not job_completed:
        logger.error("Job failed to complete")
        exit(1)

    try:
        insights_list = [insight.export_all_data() for insight in async_job.get_result()]
        return insights_list

    except Exception as e:
        logger.error(f"Error getting results: {e}")
        exit(1)

def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("partitions")
    parser.add_argument("account_id")
    parser.add_argument("table_name")
    parser.add_argument("breakdown")


    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    partitions = args.partitions
    account_id = args.account_id
    table_name = args.table_name
    breakdown = args.breakdown


    logger.info(
        f"m={JOB_NAME}, environment={env}, datalake_bucket={datalake_bucket}, table_name={table_name}, "
        f"load_start_date={load_start_date}, load_end_date={load_end_date}, partition_cols={partitions}, "
        f"msg=Starting spark job..."
    )

    insights_list = facebook_insights_request(account_id, table_name, load_start_date, load_end_date, breakdown)

    if len(insights_list) <= 0:
        logger.info("No data returned from API")
        return
    
    df = spark.createDataFrame(insights_list)

    if "impressions" not in df.columns:
        logger.info("Schema mismatch")
        return

    logger.info("DataFrame Spark created successfully")
        
    df = df.withColumn(
                "account_name_snake_case",
                udf(StringFormatter.set_alphanumeric_snake_case)(df.account_name),
            )

    df = (
        SparkDataFrameService()
        .input(df)
        .create_year_month_day_columns_from_dataframe_column("date_start")
        .output()
    )

    save_to_datalake(
        dataframe=df,
        environment=env,
        source=source,
        datalake_bucket=datalake_bucket,
        table_name=table_name,
        partitions=ast.literal_eval(partitions)
    )

if __name__ == "__main__":
    main()
