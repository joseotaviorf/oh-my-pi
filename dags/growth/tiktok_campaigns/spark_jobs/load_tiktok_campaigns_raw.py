import json
from argparse import ArgumentParser
from typing import Any, Dict, List

import requests
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import (
    BaseDBUtils,
    SparkDataFrameService,
    SparkTableStorageFormat,
)
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.metastore_services import MetastoreServiceFactory

JOB_NAME = "load_tiktok_campaigns_raw"

logger = QuintoAndarLogger(JOB_NAME)
spark_client = SparkClient(app_name=JOB_NAME)
spark = spark_client.conn
dbutils = BaseDBUtils().get_dbutils()
metastore_service = MetastoreServiceFactory.create_loader_metastore_service(
    spark_client
)

SECRET_SCOPE = "quintoandar"


def _flatten_report_row(item: Dict[str, Any]) -> Dict[str, Any]:
    dimensions = item.get("dimensions") or {}
    metrics = item.get("metrics") or {}
    row = {**dimensions, **metrics}
    if "stat_time_day" in row:
        row["dt_stat"] = row.pop("stat_time_day")
    return row


def fetch_tiktok_campaigns(
    api_base_url: str,
    endpoint_path: str,
    access_token: str,
    advertiser_ids: List[str],
    report_type: str,
    data_level: str,
    dimensions: List[str],
    metrics: List[str],
    load_start_date: str,
    load_end_date: str,
    page_size: int,
) -> List[Dict[str, Any]]:
    url = f"{api_base_url.rstrip('/')}{endpoint_path}"
    headers = {"Access-Token": access_token}
    advertiser_ids_param = json.dumps(advertiser_ids)
    all_rows: List[Dict[str, Any]] = []
    page = 1

    while True:
        params = {
            "advertiser_ids": advertiser_ids_param,
            "report_type": report_type,
            "dimensions": json.dumps(dimensions),
            "metrics": json.dumps(metrics),
            "data_level": data_level,
            "start_date": load_start_date,
            "end_date": load_end_date,
            "page": page,
            "page_size": page_size,
        }
        response = requests.get(url, headers=headers, params=params, timeout=120)
        response.raise_for_status()
        body = response.json()

        if body.get("code") != 0:
            raise ValueError(
                f"TikTok API error code={body.get('code')} message={body.get('message')}"
            )

        data = body.get("data") or {}
        items = data.get("list") or []
        for item in items:
            all_rows.append(_flatten_report_row(item))

        page_info = data.get("page_info") or {}
        current_page = int(page_info.get("page", page))
        total_page = int(page_info.get("total_page", current_page))

        if not items and page == 1:
            logger.warning(
                "m=fetch_tiktok_campaigns, msg=Empty first page from TikTok API"
            )
            break

        if current_page >= total_page:
            break

        page = current_page + 1

    return all_rows


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")

    add_validation_target_args(parser)
    args = parser.parse_args()

    if args.load_start_date > args.load_end_date:
        raise ValueError(
            f"load_start_date ({args.load_start_date}) must be <= "
            f"load_end_date ({args.load_end_date})"
        )

    config_service = ConfigurationService(args.source)
    table_name = config_service.get_config("table_name")
    raw_partition_cols = config_service.get_config("raw_partition_cols")
    api_base_url = config_service.get_config("api_base_url")
    endpoint_path = config_service.get_config("endpoint_path")
    advertiser_ids = config_service.get_config("advertiser_ids")
    report_type = config_service.get_config("report_type")
    data_level = config_service.get_config("data_level")
    page_size = config_service.get_config("page_size")
    dimensions = config_service.get_config("dimensions")
    metrics = config_service.get_config("metrics")

    credentials = json.loads(
        dbutils.secrets.get(scope=SECRET_SCOPE, key=APIEnum.TIKTOK)
    )
    access_token = credentials["value"]

    api_rows = fetch_tiktok_campaigns(
        api_base_url=api_base_url,
        endpoint_path=endpoint_path,
        access_token=access_token,
        advertiser_ids=advertiser_ids,
        report_type=report_type,
        data_level=data_level,
        dimensions=dimensions,
        metrics=metrics,
        load_start_date=args.load_start_date,
        load_end_date=args.load_end_date,
        page_size=page_size,
    )

    if api_rows:
        df = spark_client.create_dataframe(api_rows)

        datalake_info = DatalakeMetastoreService.get_db_info(
            args.environment, args.source, args.datalake_bucket
        )
        database_name = datalake_info["db_raw_databricks"]
        database_location = datalake_info["db_raw_path"]
        write_database_name, write_table_name, write_location = (
            resolve_datalake_write_target(
                prod_database=database_name,
                prod_table=table_name,
                prod_location=database_location,
                bucket=args.datalake_bucket,
                target_database=args.target_database_name,
                target_table=args.target_table_name,
            )
        )
        metastore_service.create_database(write_database_name)

        df = (
            SparkDataFrameService()
            .input(df)
            .create_year_month_day_columns_from_dataframe_column("dt_stat")
            .output()
        )

        format_options = SparkTableStorageFormat.DEFAULT_RAW
        s3_loader = S3Loader()
        s3_loader.load_df(
            df=df,
            s3_path=f"{write_location}{write_table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
        )
        spark_metastore_loader = SparkMetastoreLoader(metastore_service)
        spark_metastore_loader.update_metastore(
            df,
            write_database_name,
            write_table_name,
            format_options,
            write_location,
            raw_partition_cols,
            force_recreate=True,
        )
        metastore_service.create_new_partitions_from_df(
            database_name=write_database_name,
            table_name=write_table_name,
            df=df,
            partition_cols=raw_partition_cols,
        )
    else:
        logger.warning(
            f"m={JOB_NAME}, load_start_date={args.load_start_date}, "
            f"load_end_date={args.load_end_date}, msg=No data returned from TikTok API."
        )
