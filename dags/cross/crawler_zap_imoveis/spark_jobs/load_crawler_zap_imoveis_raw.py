import ast
import logging
import re

from argparse import ArgumentParser
from datetime import date, datetime, timedelta
from functools import reduce
from typing import List, Tuple

from pyspark.sql import DataFrame
import pyspark.sql.functions as F
from pyspark.sql.utils import AnalysisException

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.s3_consumer import S3Consumer
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services import ConfigurationService
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services.metastore_services import SparkMetastoreService

from quintoandar_logger import QuintoAndarLogger  # type: ignore

SOURCE = "crawler_zap_imoveis"
JOB_NAME = f"load_{SOURCE}_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def dates_in_range(
    source_root_path: str,
    origin: str,
    date_interval: List[date]
) -> List[Tuple[date, str]]:
    path_origin = f"{source_root_path}origin={origin}/"
    found_dates = []

    # Pre-compute for fast lookup
    date_pattern = re.compile(r"year=(\d{4})/month=(\d{2})/day=(\d{2})")
    range_years = {d.year for d in date_interval}
    range_months = {d.month for d in date_interval}

    for year_folder in dbutils.fs.ls(path_origin):
        year_match = re.search(r"year=(\d{4})", year_folder.path)
        if year_match and int(year_match.group(1)) in range_years:
            for month_folder in dbutils.fs.ls(year_folder.path):
                month_match = re.search(r"month=(\d{2})", month_folder.path)
                if month_match and int(month_match.group(1)) in range_months:
                    for day_folder in dbutils.fs.ls(month_folder.path):
                        day_match = date_pattern.search(day_folder.path)
                        if day_match:
                            year, month, day = map(int, day_match.groups())
                            dt_ingestion = datetime(year, month, day).date()
                            if dt_ingestion in date_interval:
                                found_dates.append((dt_ingestion, day_folder.path))
    logger.info(
        f"m=dates_in_range, origin={origin}\n"
        f"Found the following paths to ingest:\n{found_dates}"
    )
    return found_dates


def load_from_s3(
    ingestion_path: str,
    origin: str,
    dt_path: date
) -> DataFrame:
    cities_path = (ingestion_path + "city=*/")

    logger.info(
        f"m=load_from_s3, origin={origin}, execution_date={dt_path}, "
        f"s3_path={cities_path}, msg=Starting to load data from S3"
    )

    spark_client = SparkClient()
    s3_consumer = S3Consumer(spark_client)

    raw_df = s3_consumer.get_data_from_file(path=cities_path, format="json")

    logger.info(
        f"m=load_from_s3, origin={origin}"
        f"msg=Successfully read data from S3"
    )

    return (
        raw_df.select(
            F.col("*"),
            F.col("address.city").alias("city"),
            F.lit(dt_path.year).alias("year"),
            F.lit(dt_path.month).alias("month"),
            F.lit(dt_path.day).alias("day")
        )
        .filter(
            (F.col("city").isNotNull())
            & (F.col("city") != "")
        )
    )


def save_to_datalake(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    table_name: str,
    partitions: List[str],
) -> None:  # @todo fix code duplication with /dags/growth/iptu_bh/spark_jobs/load_iptu_bh_raw.py#L43
    spark_client = SparkClient()

    db_info = DatalakeMetastoreService.get_db_info(environment, SOURCE, datalake_bucket)
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


def main(
    datalake_bucket: str,
    environment: str,
    gchat_cred: str,
    load_start_date: str,
    load_end_date: str,
    origin: str,
    partitions: List[str],
    source_root_path: str,
    table_name: str,
) -> None:

    logger.info(
        f"""
        m=__main__, environment={environment}, source={SOURCE},datalake_bucket={datalake_bucket}, origin={origin},
        source_root_path={source_root_path}, table_name={table_name},
        load_start_date={load_start_date}, load_end_date={load_end_date}
        msg=Starting spark job...
        """
    )

    load_start_date = datetime.strptime(load_start_date, "%Y-%m-%d").date()
    load_end_date = datetime.strptime(load_end_date, "%Y-%m-%d").date()
    range_date: List[date] = [
        load_start_date + timedelta(days=x) for x in range(
            (load_end_date - load_start_date).days + 1
        )
    ]

    dfs = []
    for dt_ref, path in dates_in_range(
        source_root_path=source_root_path,
        origin=origin,
        date_interval=range_date
    ):
        try:
            df = load_from_s3(
                ingestion_path=path,
                origin=origin,
                dt_path=dt_ref
            )
            dfs.append(df)
        except AnalysisException as e:
            logger.info(
                f"""
                m=__main__,
                msg=An exception occurred, e={e}.
                """
            )
            main_error = str(e).strip().splitlines()[0] if str(e) else "Unknown error"
            message_content = (
                f"📂❌ {origin} crawler s3 folder/file validation failed for date {dt_ref}\n"
                f"Failed in the range of {load_start_date} to {load_end_date}\n"
                f"Error: {main_error}"
            )
            message = Message(content=message_content, destination=gchat_cred)
            GChatService.send_message(message)

    if dfs:
        full_df = reduce(lambda df1, df2: df1.unionByName(df2, allowMissingColumns=True), dfs)
        logger.info(
            f"""
            m=__main__,
            msg=Build dataframe with {len(dfs)} size"
            """
        )
        save_to_datalake(
            dataframe=full_df,
            environment=environment,
            datalake_bucket=datalake_bucket,
            table_name=table_name,
            partitions=partitions,
        )
    else:
        logger.warning(
            f"""
            m=__main__,
            msg=No valid S3 partitions found from {load_start_date} to {load_end_date}
            """
        )
        message_content = (
            f"📂⚠️ No data found in S3 for `{origin}` between "
            f"{load_start_date} and {load_end_date}.\n"
            f"Please check if upstream systems are delivering data."
        )
        message = Message(content=message_content, destination=gchat_cred)
        GChatService.send_message(message)


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", help="Forno/Prod values")
    parser.add_argument("datalake_bucket", help="Bucket value in forno/prod")
    parser.add_argument("table_name", help="Name of the table to store data into")
    parser.add_argument("partitions", help="Partition columns name")
    parser.add_argument("load_start_date", help="Start date to load data")
    parser.add_argument("load_end_date", help="End date to load data")
    parser.add_argument("source_root_path", help="Base path of the s3 bucket")
    parser.add_argument("origin", help="Origin of the data")

    args = parser.parse_args()

    config_service = ConfigurationService(SOURCE)
    webhook_key = config_service.get_config("notification_webhooks_keys")[
        "data_quality"
    ] # type: ignore

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    gchat_webhook = dbutils.secrets.get(
        scope="quintoandar",
        key=webhook_key
    )

    main(
        datalake_bucket=args.datalake_bucket,
        environment=args.env,
        gchat_cred=gchat_webhook,
        load_start_date=args.load_start_date,
        load_end_date=args.load_end_date,
        origin=args.origin,
        partitions=ast.literal_eval(args.partitions),
        source_root_path=args.source_root_path,
        table_name=args.table_name,
    )
