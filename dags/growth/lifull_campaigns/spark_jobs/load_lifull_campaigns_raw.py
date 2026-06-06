import json
import logging
import ssl
from argparse import ArgumentParser
from ast import literal_eval
from datetime import datetime, timedelta
from functools import reduce

import requests
from pyspark.sql import DataFrame
from quintoandar_logger import QuintoAndarLogger
from urllib3 import poolmanager

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
from bietlejuice.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_lifull_campaigns_raw"

logger = QuintoAndarLogger(JOB_NAME)


class TLSAdapter(requests.adapters.HTTPAdapter):
    """
    Solution used to solve an SLL error during API requests.
    Reference here: https://stackoverflow.com/questions/61631955/python-requests-ssl-error-during-requests
    """

    def init_poolmanager(self, connections, maxsize, block=False):
        """Create and initialize the urllib3 PoolManager."""
        context = ssl.create_default_context()
        context.set_ciphers("DEFAULT@SECLEVEL=1")

        self.poolmanager = poolmanager.PoolManager(
            num_pools=connections,
            maxsize=maxsize,
            block=block,
            ssl_version=ssl.PROTOCOL_TLS,
            ssl_context=context,
        )


def _init_http_session() -> requests.sessions.Session:
    """Create HTTP session."""
    session = requests.Session()
    session.mount("https://", TLSAdapter())

    return session


def _fetch_auth_token(
    session: requests.sessions.Session, url: str, credentials: dict, account_id: str
) -> str:
    """
    Make a POST request to fetch auth token from Thribee plataform.
    """
    try:
        session.post(
            login_url,
            data=credentials,
            cookies={"curPartner": str(account_id)},
        )
        auth_token = session.cookies.get_dict().get("user")

        return auth_token

    except Exception as exception:
        logging.error(
            f"Fail to fetch auth token from Thribee plataform. error:{exception}"
        )

        raise exception


def _fetch_campaign_data(
    login_url: str,
    credentials: dict,
    campaign_url: str,
    account: dict,
    execution_date: str,
) -> DataFrame:
    """
    Fetch raw data from a campaign for an execution date.
    """

    session = _init_http_session()

    auth_token = _fetch_auth_token(
        session, login_url, credentials, account["account_id"]
    )

    cookies = {
        "user": auth_token,
        "curPartner": str(account["account_id"]),
    }

    data = {
        "device": "",
        "startDate": execution_date,
        "endDate": execution_date,
        "ajaxCall": "1",
    }

    try:
        response = session.post(campaign_url, cookies=cookies, data=data)

        if response.status_code == 200:
            try:
                data = json.loads(response.text)["data"]["list"]["lines"]

                if len(data) > 0:
                    return spark.createDataFrame(
                        [
                            {
                                "id": str(row["campaignId"]),
                                "name": str(row["name"]),
                                "account_name": account["account_name"],
                                "clicks": str(row["clicks"]),
                                "total_cost": str(row["cost"]),
                                "desktop_cost": str(row["desktopCost"]),
                                "mobile_cost": str(row["mobileCost"]),
                                "curr_date": datetime.strptime(
                                    execution_date, "%Y-%m-%d"
                                ),
                                "group_name": str(row["groupName"]),
                                "acc": int(account["account_id"]),
                                "dt": str(execution_date),
                            }
                            for row in data
                        ]
                    )
                else:
                    logging.error(
                        f"No data found for account {account['account_name']} to date {execution_date}."
                    )

            except Exception as exception:
                logging.error(f"Fail to extract data. Schema error:{exception}")
                raise exception
        else:
            logging.error(
                f"Unsuccessful request to fetch campaign data from {campaign_url}. Status code: {response.status_code}"
            )
            raise Exception(
                f"Network error. status code response: {response.status_code}"
            )

    except Exception as exception:
        logging.error(
            f"Fail to fetch campaign data from Thribee plataform. error:{exception}"
        )
        raise exception


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("load_start_date")
    parser.add_argument("load_end_date")
    parser.add_argument("raw_table_name")
    parser.add_argument("raw_partition_cols")

    add_validation_target_args(parser)
    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    start_date = datetime.strptime(args.load_start_date, "%Y-%m-%d")
    end_date = datetime.strptime(args.load_end_date, "%Y-%m-%d")
    raw_table_name = args.raw_table_name
    raw_partition_cols = literal_eval(args.raw_partition_cols)

    config_service = ConfigurationService(source)
    accounts = config_service.get_config("accounts")
    login_url = config_service.get_config("login_url")
    campaign_url = config_service.get_config("campaign_url")

    """
    Fetch login credentials.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials = json.loads(
        dbutils.secrets.get("quintoandar", APIEnum.LIFULL_CAMPAIGNS)
    )

    """
    Fetch events data.
    """
    times_range = [
        (start_date + timedelta(n)).strftime("%Y-%m-%d")
        for n in range((end_date - start_date).days + 1)
    ]
    campaigns_data = [
        _fetch_campaign_data(
            login_url, credentials, campaign_url, accounts.get(acc), dt
        )
        for acc in accounts
        for dt in times_range
    ]

    filtered_campaign_data = list(filter(None, campaigns_data))

    if len(filtered_campaign_data) > 0:
        df = reduce(DataFrame.unionAll, filtered_campaign_data)

        """
        Load data to datalake.
        """
        spark_client = SparkClient()
        spark_context = spark_client.conn.sparkContext
        dataframe_service = SparkDataFrameService()

        db_info = DatalakeMetastoreService.get_db_info(
            environment, source, datalake_bucket
        )
        database_name = db_info["db_raw_databricks"]
        database_location = db_info["db_raw_path"]
        write_database_name, write_table_name, write_location = (
            resolve_datalake_write_target(
                prod_database=database_name,
                prod_table=raw_table_name,
                prod_location=database_location,
                bucket=datalake_bucket,
                target_database=args.target_database_name,
                target_table=args.target_table_name,
            )
        )
        format_options = SparkTableStorageFormat.DEFAULT_RAW

        spark_metastore_service = SparkMetastoreService(spark_client)
        spark_metastore_service.create_database(write_database_name)

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            s3_path=f"{write_location}{write_table_name}",
            format_options=format_options,
            partitions=raw_partition_cols,
            optimize_dataframe=False,
        )

        """
        Update metastore.
        """
        spark_metastore_loader.update_metastore(
            df,
            write_database_name,
            write_table_name,
            format_options,
            write_location,
            raw_partition_cols,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            database_name=write_database_name,
            table_name=write_table_name,
            df=df,
            partition_cols=raw_partition_cols,
        )

    else:
        logging.error(f"No data found from {start_date} to {end_date}.")
