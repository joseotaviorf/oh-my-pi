import json
import logging
from argparse import ArgumentParser

import requests
from quintoandar_logger import QuintoAndarLogger
from requests import RequestException
from requests.adapters import HTTPAdapter, Retry

from bietlejuice.base.service import ServiceEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_data_assets_into_mp"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def remove_nulls(row_dict:dict) -> dict:
    """
    Removes null values from a dictionary

    :param row_dict: dictionary to be cleaned

    :return: dictionary without null values
    """
    return {k: v for k, v in row_dict.items() if v is not None}


def _get_payloads_from_datalake(spark_client:SparkClient, data_asset:str) -> list:
    """
    This function gets the data from the reverse tables and transforms it into a list of payloads

    :param spark_client: SparkClient to connect to local spark
    :param data_asset: data asset to be loaded into Metadata Propagator. Options are dashboard, chart, dataset

    :return: list of payloads
    """
    DEAFULT_QUERY = "SELECT * FROM reverse_dashboard_governance.{asset}"
    formatted_query = DEAFULT_QUERY.format(asset=data_asset)

    df = spark_client.get_records(formatted_query)
    rows = df.rdd.map(lambda row: row.asDict()).collect()

    return [{**remove_nulls(row)} for row in rows]

def _send_requests(endpoint:str, payloads:list, chunk_size:int=30) -> None:
    """
    Sends requests with payload with 5 retries and breaks the payload into chunks if needed

    :param endpoint: endpoint to send the requests. Must have already which asset to send to
    :param payloads: list of payloads to be sent
    :param chunk_size: size of the chunks to break the payloads. Default is 30

    :return: None
    """
    session = requests.Session()
    retries = Retry(total=5, backoff_factor=1, status_forcelist=[502, 503, 504])
    session.mount(endpoint, HTTPAdapter(max_retries=retries))

    for idx in range(0, len(payloads), chunk_size):
        chunk_number = idx // chunk_size + 1
        chunk = payloads[idx: idx + chunk_size]
        logger.info(f"m=_send_requests, message=Chunk: {chunk_number}, sending {len(chunk)} items")
        response = session.post(endpoint, json=chunk)

        try:
            response.raise_for_status()
        except RequestException as exception:
            if exception.response is not None:
                logger.error(
                    f"Exception trying to call metadata-propagator service, "
                    f"status_code={exception.response.status_code}, "
                    f"error_message={exception.response.text}, "
                    f"payload={chunk}"
                )
            else:
                logger.error(
                    f"Exception trying to call metadata-propagator service, "
                    f"exception={exception}, "
                    f"payload={chunk}"
                )


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    all_data_assets = ["dashboard", "chart", "dataset"]

    parser.add_argument("environment", help="forno/prod values ")
    parser.add_argument("--data_assets", type=str, nargs="+",choices=all_data_assets,
                        help="list of data assets to be loaded into Metadata Propagator. Options are dashboard, chart, dataset")

    args = parser.parse_args()

    environment = args.environment
    data_assets = args.data_assets
    chunk_size = 30

    logger.info(
        f"""m=__main__, environment={environment}, source=dashboard_governance,
        """
    )
    error = []

    for asset in data_assets:
        logger.info(f"m=__main__, asset={asset}")
        if asset == "dashboard":
            METADATA_PROPAGATOR_PATH = "/dashboard"
        elif asset == "chart":
            METADATA_PROPAGATOR_PATH = "/chart"
            chunk_size = 200
        elif asset == "dataset":
            METADATA_PROPAGATOR_PATH = "/dataset"

        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        json_credentials = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key=ServiceEnum.METADATA_PROPAGATOR.value
        )
        credentials = json.loads(json_credentials)
        host = credentials["host"]
        endpoint = f"{host}{METADATA_PROPAGATOR_PATH}"
        logger.info(f"m=__main__, sending data to {endpoint}")

        spark_client = SparkClient()
        payloads = _get_payloads_from_datalake(spark_client, asset)
        try:
            _send_requests(endpoint, payloads, chunk_size)
        except Exception as e:
            error.append(e)
            logger.error(f"m=__main__, error={e}")

    if error:
        raise RuntimeError(f"Error sending data to Metadata Propagator: {error}")

