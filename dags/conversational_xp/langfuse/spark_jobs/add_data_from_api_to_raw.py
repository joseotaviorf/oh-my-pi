import json
import logging
from argparse import ArgumentParser
from datetime import datetime, timedelta
from concurrent.futures import ThreadPoolExecutor, as_completed
import time

from langfuse import Langfuse
from pyspark.sql.functions import lit, to_json, col

from bietlejuice.base.databricks.table_privileges import TablePrivileges
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
)
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_languse_raw"
SOURCE = "langfuse"
MAX_WORKERS = 10  # number of parallel workers for API calls
PAGE_SIZE = 100
MAX_RETRIES = 3  # number of retries for failed API calls

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def fetch_page_with_retry(langfuse, table_name, execution_date, page, limit=PAGE_SIZE, max_retries=MAX_RETRIES):
    """Fetch a single page of data with retry logic and exponential backoff."""
    for attempt in range(max_retries):
        try:
            if table_name == "scores":
                resp = langfuse.api.score_v_2.get(
                    from_timestamp=execution_date,
                    page=page,
                    limit=limit
                )
            elif table_name == "traces":
                resp = langfuse.api.trace.list(
                    from_timestamp=execution_date,
                    page=page,
                    limit=limit
                )
            elif table_name == "observations":
                resp = langfuse.api.observations.get_many(
                    from_start_time=execution_date,
                    page=page,
                    limit=limit
                )
            else:
                raise Exception(f"Table {table_name} not found")
            
            return {
                'page': page,
                'data': [json.dumps(x.dict(), default=str) for x in resp.data],
                'meta': resp.meta.dict() if hasattr(resp, 'meta') else {},
                'success': True
            }
        except Exception as e:
            if attempt < max_retries - 1:
                wait_time = 2 ** attempt  # Exponential backoff: 1, 2, 4 seconds
                logger.warning(f"Retry {attempt + 1}/{max_retries} for page {page} after {wait_time}s: {e}")
                time.sleep(wait_time)
            else:
                logger.error(f"Failed to fetch page {page} after {max_retries} attempts: {e}")
                return {'page': page, 'data': [], 'meta': {}, 'success': False}


def get_langfuse_data(langfuse, execution_date, table_name):
    """Retrieves data from Langfuse API using parallel requests for better performance."""
    limit = PAGE_SIZE
    
    logger.info(f"Fetching data starting from execution_date {execution_date}")
    logger.info(f"Using {MAX_WORKERS} workers with page size {limit}")

    first_page_result = fetch_page_with_retry(langfuse, table_name, execution_date, 1, limit)
    if not first_page_result['success']:
        logger.error(f"Failed to fetch first page after {MAX_RETRIES} retries")
        raise Exception(f"Critical error: Unable to fetch first page for table {table_name} from Langfuse API after {MAX_RETRIES} retry attempts")
    
    all_json_data = first_page_result['data']
    
    # according to Langfuse API docs, meta.totalPages should always be present
    total_pages = first_page_result['meta']['totalPages']
    logger.info(f"Total pages to fetch: {total_pages}")

    if total_pages == 1:
        logger.info(f"Only one page of data for table {table_name}")
        return all_json_data

    pages_to_fetch = list(range(2, total_pages + 1))
    
    # use only as many workers as we have pages to fetch
    num_workers = min(MAX_WORKERS, len(pages_to_fetch))

    
    with ThreadPoolExecutor(max_workers=num_workers) as executor:
        future_to_page = {
            executor.submit(fetch_page_with_retry, langfuse, table_name, 
                          execution_date, page, limit): page 
            for page in pages_to_fetch
        }
        
        # collect results as they complete
        for future in as_completed(future_to_page):
            page = future_to_page[future]
            try:
                result = future.result()
                if result['success'] and result['data']:
                    all_json_data.extend(result['data'])
                else:
                    logger.warning(f"Page {page} returned no data or failed")
            except Exception as e:
                logger.error(f"Error processing page {page}: {e}")
    
    logger.info(f"Total records fetched for table {table_name}: {len(all_json_data)}")
    return all_json_data

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name")
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("execution_date")
    parser.add_argument("table_name")

    args = parser.parse_args()
    dag_name = args.dag_name
    environment = args.env
    datalake_bucket = args.datalake_bucket
    table_name = args.table_name
    execution_date_str = args.execution_date
    # fetch last 6 hours of data
    execution_date = datetime.fromisoformat(execution_date_str) - timedelta(hours=2)
    partition_cols = ["year", "month", "day", "hour"]

    config_service = ConfigurationService(dag_name)
    langfuse_host = config_service.get_config("langfuse_host")

    logger.info(f"m=dag_name={dag_name}, environment={environment}, datalake_bucket={datalake_bucket}")
    logger.info(f"m=table_name={table_name}, execution_date={execution_date}, execution_date_str={execution_date_str}")
 

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    langfuse_pk = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key='LANGFUSE_PUBLIC_KEY')
    langfuse_sk = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key='LANGFUSE_SECRET_KEY')

    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
    s3_loader = S3Loader()

    datalake_info = DatalakeMetastoreService.get_db_info(
        environment, SOURCE, datalake_bucket
    )
    database_name = datalake_info["db_raw_databricks"]
    format_options = SparkTableStorageFormat.DEFAULT_RAW
    database_location = datalake_info["db_raw_path"]
    spark_metastore_service.create_database(database_name)

    langfuse = Langfuse(
        secret_key=langfuse_sk,
        public_key=langfuse_pk,
        host=langfuse_host
    )

    json_data = get_langfuse_data(langfuse, execution_date, table_name)

    if not json_data:
        logger.warning(f"No data found, skipping processing.")
    else:

        rdd = spark.sparkContext.parallelize(json_data)
        df = spark.read.json(rdd)

        if "metadata" in df.columns:
            df = df.withColumn("metadata", to_json(col("metadata")))
        
        df = (
            df.withColumn("year", lit(execution_date.year))
            .withColumn("month", lit(execution_date.month))
            .withColumn("day", lit(execution_date.day))
            .withColumn("hour", lit(execution_date.hour))
        )

        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=table_name,
            df=df,
            partition_cols=partition_cols,
        )

        full_raw_table_name = f"datalake_{SOURCE}_raw.{table_name}"
        table_privileges = TablePrivileges.from_environment_default(full_raw_table_name)
        if (
            table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            table_privileges.apply()
