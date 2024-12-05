import json
import tempfile
from functools import reduce
from argparse import ArgumentParser
from pyspark.sql import DataFrame
from pyspark.sql.functions import lit, element_at, to_date
from pyspark.sql.types import StructType, StructField, StringType, ArrayType

import googleapiclient.discovery
from google.oauth2.credentials import Credentials

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_google_search_console_raw"

SCOPES = [
    "https://www.googleapis.com/auth/webmasters.readonly",
    "https://www.googleapis.com/auth/webmasters",
]
API_SERVICE_NAME = "searchconsole"
API_VERSION = "v1"

logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("env")
    parser.add_argument("datalake_bucket", type=str, help="target bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("report_type")

    args = parser.parse_args()

    logger.info(
        f"""
            m={JOB_NAME}, environment={args.env}, source={args.source}, table_name=report_{args.report_type},
            load_start_date={args.load_start_date}, load_end_date={args.load_end_date}, report_type={args.report_type}, 
            msg=print spark jobs args
        """
    )

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    load_start_date = args.load_start_date
    load_end_date = args.load_end_date
    report_type = args.report_type
    table_name = f"report_{report_type}"

    config_service = ConfigurationService(source)
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    site_url_list = config_service.get_config(f"site_url_list")
    query_request_body = config_service.get_config(report_type)

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials_str = dbutils.secrets.get(
        scope="quintoandar", key=APIEnum.GOOGLE_SEARCH_CONSOLE
    )
    credentials = json.loads(credentials_str)

    tfile = tempfile.NamedTemporaryFile(suffix=".json", mode="w+")
    json.dump(credentials, tfile)
    tfile.flush()

    creds = Credentials.from_authorized_user_file(tfile.name, SCOPES)

    search_console = googleapiclient.discovery.build(
        API_SERVICE_NAME, API_VERSION, credentials=creds
    )

    spark_client = SparkClient()


    schema = StructType(
        [
            StructField("keys", ArrayType(StringType())),
            StructField("clicks", StringType()),
            StructField("impressions", StringType()),
            StructField("ctr", StringType()),
            StructField("position", StringType()),
        ]
    )

    dfs = []
    for site_url in site_url_list:
        for type in query_request_body["type_list"]:
            maxRows = 25000  # Maximum 25K per call
            numRows = 0  # Start at Row Zero
            finished = False # Initialize status of extraction
            while not finished:  # As long as data have not been fully extracted.
                request_body = {
                    "startDate": load_start_date,
                    "endDate": load_end_date,
                    "dimensions": query_request_body["dimensions"],
                    "aggregationType": query_request_body["aggregation_type"],
                    "type": type,
                    "rowLimit": maxRows,  # Set number of rows to extract at once (max 25k)
                    "startRow": numRows,  # Start at row 0, then row 25k, then row 50k... until with all.
                    "dimensionFilterGroups": [{
                    'filters': query_request_body["filters"]
                  }],
                }

                query_result = (
                    search_console.searchanalytics()
                    .query(siteUrl=site_url, body=request_body)
                    .execute()
                )

                if "rows" in query_result:
                    numRows = numRows + len(query_result["rows"])

                    df_site_url = spark_client.conn.createDataFrame(
                        query_result["rows"], schema
                    )

                    df_site_url = (
                        df_site_url.withColumn("site_url", lit(site_url))
                        .withColumn("type", lit(type))
                        .withColumn(
                            "date",
                            to_date(
                                element_at(
                                    df_site_url["keys"],
                                    query_request_body["dimensions"].index("DATE") + 1,
                                ),
                                "yyyy-MM-dd",
                            ),
                        )
                    )

                    dfs.append(df_site_url)
                else:
                    finished = True  # If no response left, change status

                if numRows % maxRows != 0:  # If numRows not divisible by 25k...
                    finished = True  # change status, you have covered all lines.

            logger.info(
                f"""
                    m={JOB_NAME}, {numRows} rows extracted for site_url={site_url},
                    for the period {load_start_date} to {load_end_date}.
                """
            )

    if dfs:
        df = reduce(DataFrame.unionAll, dfs)
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
            s3_path=f"{database_location}{table_name}",
            partitions=raw_partition_cols,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=table_name,
            format_options=SparkTableStorageFormat.DEFAULT_RAW,
            database_location=database_location,
            partitions=raw_partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=database_name,
            table_name=table_name,
            partition_cols=raw_partition_cols,
        )
    else:
        logger.info(f"m=__main__, msg=df empty.")
