import json
import logging
import time
from argparse import ArgumentParser
from datetime import datetime

import requests
from quintoandar_logger import QuintoAndarLogger
from requests import RequestException

from bietlejuice.jobs.composer.base.service import ServiceEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.clients.db_clients import SparkClient

JOB_NAME = "send_bigid_entities_to_metadata_propagator"
DATABRICKS_SCOPE = "quintoandar"
EXTRACTION_QUERY = (
    "select database_name, table_name, column_name, is_pii, is_sensitive, access_level "
    "from datalake_bigid.bigid_entities_access_level"
)
PRODUCT_ENTITY_PATH = "/productEntity"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_payloads_from_datalake_bigid(spark_client):
    query = EXTRACTION_QUERY
    df = spark_client.get_records(query)
    rows = df.collect()
    rows_dict = extract_dict_from_rows(rows)
    payloads = build_payloads(rows_dict)

    return payloads


def extract_dict_from_rows(rows):
    rows_dict = {}
    for row in rows:
        # TODO: transform to lowercase on enrich instead of here
        db_name = str.lower(row["database_name"])
        table_name = str.lower(row["table_name"])
        column = str.lower(row["column_name"])
        tags = []
        if row["is_pii"]:
            tags.append("PII")
        if row["is_sensitive"]:
            tags.append("Sensitive")
        access_level = row["access_level"]
        if access_level:
            tags.append(access_level)

        if db_name not in rows_dict:
            rows_dict[db_name] = {}

        if table_name not in rows_dict[db_name]:
            rows_dict[db_name][table_name] = {}

        rows_dict[db_name][table_name][column] = tags
    return rows_dict


def build_payloads(rows_dict):
    payloads = []
    for db_name in rows_dict:
        for table_name in rows_dict[db_name]:
            columns = rows_dict[db_name][table_name]
            payloads.append(
                {
                    "vendor": ["atlas"],
                    "database_name": db_name,
                    "table_name": table_name,
                    "columns": columns,
                }
            )
    return payloads


def send_requests(endpoint, payloads):
    logger.info(
        f"m=send_requests, len_payloads={len(payloads)}, msg=Sending request..."
    )
    try:
        response = requests.post(endpoint, json=payloads)
        response.raise_for_status()
        logger.info(
            f"Metadata sent to metadata-propagator service, response={response}"
        )
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
    endpoint = f"{host}{PRODUCT_ENTITY_PATH}"

    spark_client = SparkClient()
    payloads = get_payloads_from_datalake_bigid(spark_client)
    send_requests(endpoint, payloads)
