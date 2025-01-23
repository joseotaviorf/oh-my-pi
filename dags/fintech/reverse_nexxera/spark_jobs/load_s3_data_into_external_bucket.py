import io
import logging
from datetime import datetime
from argparse import ArgumentParser
from http.client import HTTPException

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.services.s3_service import S3Service
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.base.spark import BaseDBUtils

import boto3
from pyspark.sql.utils import AnalysisException

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_s3_data_into_external_bucket"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def __get_first_layer_folders_s3(bucket, prefix):
    s3_resource = boto3.resource("s3")
    datalakebucket = s3_resource.Bucket(bucket)
    tables = set()
    for object_summary in datalakebucket.objects.filter(Prefix=prefix):
        first_level = object_summary.key.split(prefix)[1]
        first_level = first_level.split("/")[0]
        tables.add(first_level)
    return tables

if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment", help="forno/prod values ")
    parser.add_argument("datalake_bucket", help="bucket for forno/prod datalake")
    parser.add_argument("source", help="source name")
    parser.add_argument("external_bucket", help="bucket destination for files")
    parser.add_argument("execution_date",  help="DAG execution date") #type=str,

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    external_bucket = args.external_bucket
    execution_date = args.execution_date

    logger.info(
        f"""m=__main__, environment={environment}, source={source}, execution_date={execution_date},
        datalake_bucket={datalake_bucket}, external_bucket={external_bucket},
        """
    )
    datalake_path_prefix = f"reverse/{source}/"
    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    config_service = ConfigurationService(f"reverse_{source}")


    tables = __get_first_layer_folders_s3(datalake_bucket, datalake_path_prefix)
    tables_config = config_service.get_config("tables")
    execution_date = datetime.strptime(execution_date, "%Y-%m-%d").date()

    s3_client = boto3.client("s3")

    for table in tables:
        if [conf for conf in tables_config if conf['table_name'] == table]:
            table_config = [conf for conf in tables_config if conf['table_name'] == table][0]
        if table_config.get("is_monthly", False) and execution_date.day != 1:
            logger.info(
                    f"m=__main__, message={table} is monthly and should not run today, execution_date={execution_date}"
                )
            continue

        datalake_path = f"s3://{datalake_bucket}/{datalake_path_prefix}{table}/year={execution_date.year}/month={execution_date.month}/day={execution_date.day}"
        files = S3Service(boto3.resource("s3")).list_objects(datalake_path)
        if len(files) > 0:
            try:
                df = s3_consumer.get_data_from_file(path=datalake_path, format="parquet")
            except AnalysisException as e:
                logger.info(
                        f"m=__main__, message=AnalysisException for {table}, datalake_path={datalake_path}, exception: {e}"
                    )
                continue
        else:
            logger.info(
                    f"m=__main__, message=Found 0 files for {table}, datalake_path={datalake_path}, len(files): {len(files)}"
                )
            continue

        if df is not None:
            df = df.drop("year", "month", "day")
            if table_config.get("is_monthly", True):
                destination_path = f"{execution_date.year}/{execution_date.month:02d}/{execution_date.day:02d}/monthly/"
                table = table.replace('monthly_','')
                file_name = (
                f'{table}_{(execution_date.strftime("%Y_%m_%d"))}.csv'
                )

            else:
                destination_path = f"{execution_date.year}/{execution_date.month:02d}/{execution_date.day:02d}/daily/"
                file_name = (
                    f'{table}_{(execution_date.strftime("%Y_%m_%d"))}.csv'
                )

            with io.StringIO() as csv_buffer:
                df.toPandas().convert_dtypes().to_csv(
                    csv_buffer, index=False, header=True
                )

                response = s3_client.put_object(
                    Bucket=external_bucket,
                    Key=destination_path + file_name,
                    Body=csv_buffer.getvalue(),
                    ACL="bucket-owner-full-control",
                )

                status = response.get("ResponseMetadata", {}).get("HTTPStatusCode")

                if status == 200:
                    logger.info(
                        f"m=__main__, message=successful S3 put_object for table {table}, status={status}"
                    )
                else:
                    raise HTTPException(
                        f"m=__main__, message=UNSUCCESSFULL S3 put_object for table {table}, status={status}"
                    )
