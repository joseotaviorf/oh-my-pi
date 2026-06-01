import json
import logging
from argparse import ArgumentParser
from datetime import datetime

import requests
from quintoandar_logger import QuintoAndarLogger
from requests import RequestException
from requests.adapters import HTTPAdapter, Retry

from bietlejuice.base.service.service_enum import ServiceEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_dashboard_governance_into_mp"
DASHBOARDS_PATH = "/dashboard"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def remove_nulls(row_dict):
    return {k: v for k, v in row_dict.items() if v}


def _get_payloads_from_datalake(
    spark_client,
    execution_date,
    database_name="datalake_dashboard_governance",
    table_name="dashboard_metadata",
):
    query = """
SELECT
  platform,
  id_dashboard,
  dashboard_path,
  title,
  description,
  ownership,
  domain,
  status,
  ids_charts,
  date_format(last_view, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") as last_view,
  dashboard_url
FROM
  {database_name}.{table_name}
WHERE
  day == {day} and month == {month} and year == {year}
"""
    query_params = {
        "database_name": database_name,
        "table_name": table_name,
        "day": execution_date.day,
        "month": execution_date.month,
        "year": execution_date.year,
    }
    formatted_query = query.format(**query_params)

    df = spark_client.get_records(formatted_query)
    rows = df.rdd.map(lambda row: row.asDict()).collect()

    return [{"vendor": ["datahub"], **remove_nulls(row)} for row in rows]


def _send_requests(endpoint, payloads, chunk_size=30):
    session = requests.Session()
    retries = Retry(total=5, backoff_factor=1, status_forcelist=[502, 503, 504])
    session.mount(endpoint, HTTPAdapter(max_retries=retries))

    for idx in range(0, len(payloads), chunk_size):
        chunk = payloads[idx : idx + chunk_size]
        response = session.post(endpoint, json=chunk)

        try:
            response.raise_for_status()
        except RequestException as exception:
            if exception.response is not None:
                logger.error(
                    f"Exception trying to call metadata-propagator service, "
                    f"status_code={exception.response.status_code}, "
                    f"error_message={exception.response.text}"
                )
            else:
                logger.error(
                    f"Exception trying to call metadata-propagator service, "
                    f"exception={exception}"
                )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("execution_date_str")

    add_validation_target_args(parser)
    args = parser.parse_args()
    env = args.env
    execution_date_str = args.execution_date_str
    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    logger.info(
        f"""m={JOB_NAME}, env={env}, execution_date_str={execution_date_str}
        msg=Job execution started."""
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(
        scope=DATABRICKS_SCOPE, key=ServiceEnum.METADATA_PROPAGATOR.value
    )
    credentials = json.loads(json_credentials)
    host = credentials["host"]
    endpoint = f"{host}{DASHBOARDS_PATH}"

    database_name, table_name, _ = resolve_datalake_write_target(
        prod_database="datalake_dashboard_governance",
        prod_table="dashboard_metadata",
        prod_location="",
        bucket="",
        target_database=args.target_database_name,
        target_table=args.target_table_name,
    )

    spark_client = SparkClient()
    payloads = _get_payloads_from_datalake(
        spark_client, execution_date, database_name, table_name
    )
    _send_requests(endpoint, payloads)
