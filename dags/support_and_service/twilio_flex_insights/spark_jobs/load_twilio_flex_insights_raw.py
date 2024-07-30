import json
import logging
from argparse import ArgumentParser
from pyspark.sql.functions import unix_timestamp, to_timestamp, to_date

from quintoandar_logger import QuintoAndarLogger
from quintoandar_twilio_flex_insights_api_client.clients import TwilioFlexInsightsClient
from quintoandar_twilio_flex_insights_api_client.consumers import (
    TwilioFlexInsightsConsumer,
)
from quintoandar_twilio_flex_insights_api_client.constants.endpoint_enum import (
    EndpointEnum,
)

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkTableStorageFormat,
    SparkDataFrameService,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.formatters import StringFormatter
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_twilio_flex_insights_raw"
SOURCE = "twilio_flex_insights"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("raw_table_name")
    parser.add_argument("partition_cols")
    parser.add_argument("table_details")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    table_details = json.loads(args.table_details)
    raw_table_name = args.raw_table_name
    partition_cols = args.partition_cols

    logger.info(
        f"""
            m={JOB_NAME}, environment={environment}, datalake_bucket={datalake_bucket},
            source={SOURCE}, partition_cols={partition_cols}, raw_table_name={raw_table_name},
            msg=print spark jobs args"
        """
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = json.loads(
        dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.TWILIO_FLEX_INSIGHTS)
    )
    json_credentials = {
        "email": json_credentials["email"],
        "pwd": json_credentials["pwd"],
    }

    twilio_flex_insights_client = TwilioFlexInsightsClient(credentials=json_credentials)
    twilio_flex_insights_consumer = TwilioFlexInsightsConsumer(
        endpoint=EndpointEnum.REPORTS_CONSUMER.value, client=twilio_flex_insights_client
    )

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

    workspace_id = table_details["workspace_id"]
    object_id = table_details["object_id"]
    column_create_date = table_details["column_create_date"]

    twilio_flex_insights_consumer.client.refresh_token()
    report_link = twilio_flex_insights_consumer.get_report_link(workspace_id, object_id)

    response = twilio_flex_insights_consumer.sync(report_link).splitlines()

    response_rdd = spark_client.conn.sparkContext.parallelize(response)

    # removing empty lines
    response_rdd = response_rdd.filter(lambda x: x)

    # formatting the text in columns
    response_rdd = response_rdd.map(lambda x: x.replace('"', "").split(","))

    # Getting the first row as a header and stripping it from the response
    header = response_rdd.first()
    response_rdd = response_rdd.filter(lambda line: line != header)

    if not response_rdd.isEmpty():
        df = spark_client.create_dataframe(response_rdd)

        # Redefining dataframe column names
        header = list(
            map(lambda column_name: StringFormatter.set_snake_case(column_name), header)
        )
        df = df.toDF(*header)

        df = df.withColumn(
            column_create_date,
            to_date(to_timestamp(unix_timestamp(column_create_date, "MM/dd/yyyy"))),
        )
        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column(column_create_date)
            .output()
        )

        # loaders
        s3_loader.load_df(
            df=df,
            s3_path=f"{database_location}{raw_table_name}",
            format_options=format_options,
            partitions=partition_cols,
        )

        spark_metastore_loader.update_metastore(
            df=df,
            database_name=database_name,
            table_name=raw_table_name,
            format_options=format_options,
            database_location=database_location,
            partitions=partition_cols,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=database_name,
            table_name=raw_table_name,
            df=df,
            partition_cols=partition_cols,
        )
    else:
        raise Exception(
            f"""m=__main__, table_name={raw_table_name},
            msg=No data returned from API."""
        )

    twilio_flex_insights_consumer.client.close()
