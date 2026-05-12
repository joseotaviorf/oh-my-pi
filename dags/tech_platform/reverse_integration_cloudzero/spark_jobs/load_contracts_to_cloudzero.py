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
from bietlejuice.clients.db_clients import SparkClient

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_contracts_to_cloudzero"

logging.getLogger("py4j").setLevel(logging.INFO)
logger = QuintoAndarLogger(JOB_NAME)


def get_contracts_count_from_trino(spark_client: SparkClient, execution_date: str) -> int:
    """
    This function gets the contracts count from the reverse table and returns the total count

    :param spark_client: SparkClient to connect to local spark
    :param execution_date: Date to query contracts for (YYYY-MM-DD format)

    :return: Number of contracts for the given date
    """
    DEFAULT_QUERY = "SELECT * FROM reverse_integration_cloudzero.contracts_count"

    df = spark_client.get_records(DEFAULT_QUERY)
    rows = df.rdd.map(lambda row: row.asDict()).collect()

    if rows:
        # Get the contracts count from the first row
        contracts_count = rows[0].get('contracts_count', 0)
        logger.info(f"m=get_contracts_count_from_trino, execution_date={execution_date}, contracts_count={contracts_count}")
        return contracts_count
    else:
        logger.info(f"m=get_contracts_count_from_trino, execution_date={execution_date}, no_contracts_found")
        return 0


def send_to_cloudzero(contracts_count: int, execution_date: str, cloudzero_token: str) -> None:
    """
    Send contracts count to CloudZero API.

    :param contracts_count: Number of contracts to send
    :param execution_date: Date of the data (YYYY-MM-DD format)
    :param cloudzero_token: CloudZero API token

    :return: None
    """
    # Prepare payload
    payload = {
        "records": [
            {
                "granularity": "MONTHLY",
                "timestamp": execution_date,
                "value": contracts_count
            }
        ]
    }

    # API endpoint
    url = "https://api.cloudzero.com/unit-cost/v1/telemetry/metric/quintoandar_contracts_ongoing_rentals/replace"

    # Headers
    headers = {
        'Authorization': cloudzero_token,
        'content-type': 'application/json'
    }

    # Setup session with retries
    session = requests.Session()
    retries = Retry(total=5, backoff_factor=1, status_forcelist=[502, 503, 504])
    session.mount('https://', HTTPAdapter(max_retries=retries))

    # Add SSL configuration to handle potential SSL issues
    session.verify = True
    session.trust_env = False

    try:
        logger.info(f"m=send_to_cloudzero, sending_data={payload}")
        response = session.post(url, headers=headers, json=payload)
        response.raise_for_status()

        logger.info(f"m=send_to_cloudzero, success, status_code={response.status_code}")
        logger.info(f"m=send_to_cloudzero, response={response.text}")

    except RequestException as e:
        if e.response is not None:
            logger.error(
                f"m=send_to_cloudzero, error, status_code={e.response.status_code}, "
                f"error_message={e.response.text}, payload={payload}"
            )
        else:
            logger.error(f"m=send_to_cloudzero, error={e}, payload={payload}")
        raise


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("execution_date", help="Execution date in YYYY-MM-DD format")

    args = parser.parse_args()
    environment = args.environment
    execution_date = args.execution_date

    logger.info(f"m=__main__, environment={environment}, execution_date={execution_date}")

    try:
        # Get CloudZero token from Databricks secrets
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        logger.info(f"m=__main__, Getting credentials from Databricks secrets")
        json_credentials = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="CLOUDZERO_API_TOKEN"
        )
        try:
            credentials_dict = json.loads(json_credentials)
        except Exception as e:
            logger.error(f"m=__main__, error_parsing_json_credentials, error={e}")
            raise RuntimeError(f"Error parsing CLOUDZERO_API_TOKEN secret as JSON: {e}")

        if not isinstance(credentials_dict, dict) or "token" not in credentials_dict:
            logger.error(f"m=__main__, missing_token_key_in_credentials")
            raise RuntimeError("CLOUDZERO_API_TOKEN secret does not contain a 'token' key.")
        cloudzero_token = credentials_dict["token"]

        # Initialize Spark client
        spark_client = SparkClient()

        # Get contracts count from Trino
        contracts_count = get_contracts_count_from_trino(spark_client, execution_date)

        # Send to CloudZero
        send_to_cloudzero(contracts_count, execution_date, cloudzero_token)

        logger.info(f"m=__main__, success, contracts_count={contracts_count}")

    except Exception as e:
        logger.error(f"m=__main__, error={e}")
        raise RuntimeError(f"Error in {JOB_NAME}: {e}")
