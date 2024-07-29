from argparse import ArgumentParser
from itertools import product
from pyspark.sql.functions import lit, udf
import json
import time

from google.ads.googleads.client import GoogleAdsClient
from google.ads.googleads.errors import GoogleAdsException
from google.protobuf.json_format import MessageToDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    BaseSparkContext,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.formatters import StringFormatter
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_google_ads_raw"

# Timeout between retries in seconds.
BACKOFF_FACTOR = 5
# Maximum number of retries for errors.
MAX_RETRIES = 5

logger = QuintoAndarLogger(JOB_NAME)


def _list_customer_ids(client, customer_id, customer_filter):
    customers_query = f"""
    SELECT
        customer_client.id
    FROM
        customer_client
    WHERE
        customer_client.level <= 2
        AND customer_client.manager = FALSE
        AND customer_client.hidden = FALSE
        AND customer_client.status = ENABLED
        AND customer_client.descriptive_name {customer_filter} """
    googleads_service = client.get_service("GoogleAdsService")
    response = googleads_service.search(
        customer_id=str(customer_id), query=customers_query
    )
    return [str(row.customer_client.id) for row in response.results]


def _issue_search_request(args):
    """Issues a search request using streaming and returns a JSON list.

    Retries if a GoogleAdsException is caught, until MAX_RETRIES is reached.

    Args:
        client: an initialized GoogleAdsClient instance.
        customer_id: a client customer ID str.
        query: a GAQL query str.
    """
    client, customer_id, query = args
    ga_service = client.get_service("GoogleAdsService")
    retry_count = 0
    # Retries until reaches MAX_RETRIES or receives a successfull response
    while True:
        try:
            stream = ga_service.search_stream(customer_id=customer_id, query=query)
            # To avoid PicklingError when using a list of GoogleAdsRows
            # we put the GoogleAdsRow data into a json list result.
            json_result = []
            for batch in stream:
                for row in batch.results:
                    json_row = MessageToDict(row._pb)
                    json_result.append(json_row)
            return (True, json_result)
        except GoogleAdsException as ex:
            # This example retries on all GoogleAdsExceptions. In practice,
            # developers might want to limit retries to only those error codes
            # they deem retriable.
            if retry_count < MAX_RETRIES:
                retry_count += 1
                time.sleep(retry_count * BACKOFF_FACTOR)
            else:
                return (False, [ex, customer_id])


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("report_type")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    report_type = args.report_type

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    customer_filter = config_service.get_config("customer_filter")
    login_customer_id = config_service.get_config("login_customer_id")
    gaql_query = config_service.get_config("GAQL")[report_type]
    report_type_mapped = config_service.get_config("report_type_mapping")[report_type]

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials_str = dbutils.secrets.get(scope="quintoandar", key=APIEnum.GOOGLE_ADS)
    credentials = json.loads(credentials_str)

    googleads_client = GoogleAdsClient.load_from_dict(credentials, version="v15")
    googleads_client.login_customer_id = login_customer_id
    customer_ids = _list_customer_ids(
        googleads_client, login_customer_id, customer_filter
    )

    args = product(
        [googleads_client],
        customer_ids,
        [
            gaql_query.format(
                load_start_date=load_start_date, load_end_date=load_end_date
            )
        ],
    )
    results = BaseSparkContext.sc.parallelize(args).map(_issue_search_request).collect()

    successes = []
    failures = []
    for res in results:
        if res[0]:
            successes.append(res[1])
        else:
            failures.append(res[1])

    logger.info(
        f"m=__main__, msg=Total successful results: {len(successes)} "
        f"Total failed results: {len(failures)}"
    )

    if len(failures):
        for failure in failures:
            exc, cid = failure
            error_details = "\n"
            for error in exc.failure.errors:
                error_details += f'\tError with message "{error.message}".'
                if error.location:
                    for field_path_element in error.location.field_path_elements:
                        error_details += (
                            f"\n\t\tOn field: {field_path_element.field_name}"
                        )
            logger.error(
                f"request_id={exc.request_id}, "
                f"status={exc.error.code().name}, "
                f"customer_id={cid}, details={error_details}"
            )
        raise GoogleAdsException

    spark_client = SparkClient()
    df = spark_client.conn.read.json(BaseSparkContext.sc.parallelize(successes))

    if not df.rdd.isEmpty():
        df = (
            df.withColumn(
                "account_snake_case",
                udf(StringFormatter.set_alphanumeric_snake_case)(
                    df.customer.descriptiveName
                ),
            )
            .withColumn("report_type", lit(report_type_mapped))
            .withColumn("dt_created", df["segments.date"])
        )
        s3_loader = S3Loader()
        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

        db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        spark_metastore_service.create_database(database_name)

        s3_loader.load_df(
            df=df,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            s3_path=f"{database_location}{report_type}",
            partitions=raw_partition_cols,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=report_type,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            database_location=database_location,
            partitions=raw_partition_cols,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=report_type,
            partition_cols=raw_partition_cols,
        )
