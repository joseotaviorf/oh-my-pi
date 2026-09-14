import io
import logging
from argparse import ArgumentParser
from datetime import datetime
from http.client import HTTPException

import boto3
from pyspark.sql.functions import col
from pyspark.sql.utils import AnalysisException
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import add_validation_target_args
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "load_s3_data_into_external_bucket"
CROSS_ACCOUNT_OBJECT_ACL = "bucket-owner-full-control"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def _table_config(tables_config, table_name):
    matches = [conf for conf in tables_config if conf["table_name"] == table_name]
    if not matches:
        return None
    return matches[0]


def _read_partition(spark, datalake_bucket, source, table_name, execution_date):
    """Read the reverse table partition as Delta, falling back to Parquet."""
    table_path = f"s3://{datalake_bucket}/reverse/{source}/{table_name}"
    fqn = f"reverse_{source}.{table_name}"
    try:
        df = spark.table(fqn)
    except AnalysisException:
        try:
            df = spark.read.format("delta").load(table_path)
        except AnalysisException:
            df = spark.read.parquet(table_path)
    return df.filter(
        (col("year") == execution_date.year)
        & (col("month") == execution_date.month)
        & (col("day") == execution_date.day)
    )


def _export_table(
    spark,
    s3_client,
    datalake_bucket,
    source,
    external_bucket,
    table_name,
    table_config,
    execution_date,
):
    if table_config.get("is_monthly", False) and execution_date.day != 1:
        logger.info(
            "m=_export_table, message=%s is monthly and should not run today, "
            "execution_date=%s",
            table_name,
            execution_date,
        )
        return

    try:
        df = _read_partition(spark, datalake_bucket, source, table_name, execution_date)
    except AnalysisException as error:
        logger.info(
            "m=_export_table, message=AnalysisException for %s, exception=%s",
            table_name,
            error,
        )
        return

    if df.rdd.isEmpty():
        logger.info(
            "m=_export_table, message=Found 0 rows for %s on %s",
            table_name,
            execution_date,
        )
        return

    df = df.drop("year", "month", "day")
    is_monthly = table_config.get("is_monthly", False)
    cadence = "monthly" if is_monthly else "daily"
    destination_path = (
        f"{execution_date.year}/{execution_date.month:02d}/"
        f"{execution_date.day:02d}/{cadence}/"
    )
    export_name = table_name.replace("monthly_", "") if is_monthly else table_name
    file_name = f"{export_name}_{execution_date.strftime('%Y_%m_%d')}.csv"

    with io.StringIO() as csv_buffer:
        df.toPandas().convert_dtypes().to_csv(csv_buffer, index=False, header=True)
        response = s3_client.put_object(
            Bucket=external_bucket,
            Key=destination_path + file_name,
            Body=csv_buffer.getvalue(),
            ACL=CROSS_ACCOUNT_OBJECT_ACL,
        )

    status = response.get("ResponseMetadata", {}).get("HTTPStatusCode")
    if status == 200:
        logger.info(
            "m=_export_table, message=successful S3 put_object for table %s, status=%s",
            table_name,
            status,
        )
        return
    raise HTTPException(
        f"m=_export_table, message=UNSUCCESSFULL S3 put_object for table "
        f"{table_name}, status={status}"
    )


def main():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket for forno/prod datalake")
    parser.add_argument("source", help="source name")
    parser.add_argument("table_name", help="reverse table to export")
    parser.add_argument("execution_date", help="DAG execution date YYYY-MM-DD")
    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    table_name = args.table_name
    execution_date = datetime.strptime(args.execution_date, "%Y-%m-%d").date()

    config_service = ConfigurationService(f"reverse_{source}")
    external_bucket = config_service.get_config("external_s3_bucket")
    tables_config = config_service.get_config("tables")
    table_config = _table_config(tables_config, table_name)
    if table_config is None:
        logger.info(
            "m=main, message=table %s is not in reverse_%s config, skipping",
            table_name,
            source,
        )
        return

    logger.info(
        "m=main, environment=%s, source=%s, table_name=%s, "
        "execution_date=%s, datalake_bucket=%s, external_bucket=%s",
        environment,
        source,
        table_name,
        execution_date,
        datalake_bucket,
        external_bucket,
    )

    spark_client = SparkClient(app_name=JOB_NAME)
    s3_client = boto3.client("s3")
    _export_table(
        spark_client.conn,
        s3_client,
        datalake_bucket,
        source,
        external_bucket,
        table_name,
        table_config,
        execution_date,
    )


if __name__ == "__main__":
    main()
