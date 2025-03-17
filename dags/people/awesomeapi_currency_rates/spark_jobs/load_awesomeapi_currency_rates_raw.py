import json
import requests
import argparse
from tenacity import retry, stop_after_attempt
from pyspark.sql.functions import current_timestamp, lit
from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import SparkTableStorageFormat
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader

JOB_NAME = "load_awesomeapi_currency_rates_raw"
logger = QuintoAndarLogger(JOB_NAME)
DATABRICKS_SCOPE = "people"
API_URL = "https://economia.awesomeapi.com.br/json/daily"

@retry(stop=stop_after_attempt(1))
def get_exchange_rates(currency, start_date, end_date):
    formatted_start_date = start_date.replace("-", "")
    formatted_end_date = end_date.replace("-", "")
    url = f"{API_URL}/{currency}/?start_date={formatted_start_date}&end_date={formatted_end_date}"
    logger.info(f"m={JOB_NAME}, msg=Fetching exchange rates from {url}")

    try:
        response = requests.get(url)
        response.raise_for_status()
        data = response.json()
        if not data:
            raise ValueError(f"No exchange rate data found for {currency} from {start_date} to {end_date}")

        logger.info(f"m={JOB_NAME}, msg=Fetched {len(data)} records for {currency}")
        return data
    except Exception as e:
        logger.exception(f"m={JOB_NAME}, msg=Error fetching exchange rates: {e}")
        raise

def load_raw(spark_client, df, environment, source, datalake_bucket, table_name):
    if df is None or df.count() == 0:
        raise Exception(f"m={JOB_NAME}, msg=DataFrame is empty, failing load_raw.")

    db_info = DatalakeMetastoreService.get_db_info(environment, source, datalake_bucket)
    database_name = db_info["db_raw_databricks"]
    database_location = db_info["db_raw_path"]
    logger.info(f"m={JOB_NAME}, msg=Loading DataFrame to {database_location}{table_name}")

    metastore_service = SparkMetastoreService(spark_client)
    metastore_service.create_database(database_name)

    s3_loader = S3Loader()
    s3_loader.load_df(df=df, s3_path=f"{database_location}{table_name}", format_options=SparkTableStorageFormat.DEFAULT_RAW)

    SparkMetastoreLoader(metastore_service).update_metastore(
        df=df, database_name=database_name, table_name=table_name,
        format_options=SparkTableStorageFormat.DEFAULT_RAW, force_recreate=True,
        database_location=database_location,
    )

    metastore_service.refresh_table(database_name, table_name)
    logger.info(f"m={JOB_NAME}, msg=Successfully loaded data into {database_name}.{table_name}")

def get_parser():
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("source", help="name of the source")
    parser.add_argument("table_name", help="name of the table")
    parser.add_argument("execution_date", help="execution date in str format")
    parser.add_argument("extraction_type", help="Extraction type: full or incremental")
    parser.add_argument("load_start_date", help="Start date in YYYY-MM-DD format")
    parser.add_argument("load_end_date", help="End date in YYYY-MM-DD format")
    parser.add_argument("currencies", help="Currency pair (ex: MXN-BRL, ARS-BRL, USD-BRL, EUR-BRL)")
    return parser

if __name__ == "__main__":
    parser = get_parser()
    args = parser.parse_args()
    spark_client = SparkClient()

    logger.info(f"m={JOB_NAME}, msg=Starting job with parameters: {vars(args)}")
    currencies = json.loads(args.currencies)
    logger.info(f"m={JOB_NAME}, msg=Processing currencies: {currencies}")

    dataframes = []
    try:
        for currency in currencies["currencies"]:
            response_data = get_exchange_rates(currency, args.load_start_date, args.load_end_date)
            df_currency = spark_client.create_dataframe(response_data) \
                .withColumn("currency_pair", lit(currency)) \
                .withColumn("ts_load", current_timestamp())
            dataframes.append(df_currency)

        if not dataframes:
            raise Exception(f"m={JOB_NAME}, msg=No exchange rate data fetched, failing job.")

        df_final = dataframes[0]
        for df in dataframes[1:]:
            df_final = df_final.unionByName(df)

        logger.info(f"m={JOB_NAME}, msg=Final DataFrame created with {df_final.count()} records")
        load_raw(spark_client, df_final, args.environment, args.source, args.datalake_bucket, args.table_name)
        logger.info(f"m={JOB_NAME}, msg=Job successfully completed!")

    except Exception as e:
        logger.exception(f"m={JOB_NAME}, msg=Job failed: {e}")
        raise
