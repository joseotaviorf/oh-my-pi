import logging
import json
import os
from typing import Any
from argparse import ArgumentParser

from bietlejuice.base.api import APIEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.gsheets_service import GsheetsService

from quintoandar_logger import QuintoAndarLogger
from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from googleapiclient.discovery import build
from google.oauth2.service_account import Credentials

JOB_NAME = "load_ingested_gsheets_id_info"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

SCOPES = [
    "https://www.googleapis.com/auth/spreadsheets.readonly",
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/drive",
    "https://www.googleapis.com/auth/drive.appdata",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/drive.metadata",
    "https://www.googleapis.com/auth/drive.metadata.readonly"
]


def build_scoped_credentials(credentials) -> Credentials:
    credential = Credentials.from_service_account_info(credentials)
    scoped_credentials = credential.with_scopes(SCOPES)

    return scoped_credentials


def build_drive_api_service(scoped_credentials) -> Any:
    drive_service = build("drive", "v3", credentials=scoped_credentials)
    return drive_service


def __get_auth(dbutils, credentials_scope, credentials_key):
    """
    This method gets credentials from the Gsheets API.
    @param dbutils: DBUtils.
    @return: dict and str
    """
    credentials = json.loads(
        dbutils.secrets.get(scope=credentials_scope, key=credentials_key)
    )
    scope = credentials.pop("scope")
    return credentials, scope


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("dag_name")
    parser.add_argument("credentials_key", help="Credentials to access the Google Sheets API")
    parser.add_argument("credentials_scope", help="Databricks secret scope")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    dag_name = args.dag_name
    credentials_key = args.credentials_key
    credentials_scope = args.credentials_scope

    config_service = ConfigurationService(dag_name)
    sheet_details = config_service.get_config("sheets_info")

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    credentials, scope = __get_auth(dbutils, credentials_scope, credentials_key)
    gsheets_client = GoogleSheetsClient(credentials, scope)

    scoped_credentials = build_scoped_credentials(credentials)
    drive_service = build_drive_api_service(scoped_credentials)

    gsheets_service = GsheetsService()

    sheet_details_dict = {}
    sheets_to_be_ingested = []

    for raw_table_name, sheet_info in sheet_details.items():
        sheet_details_dict[raw_table_name] = sheet_info
        sheet_details_dict[raw_table_name]['dag_name'] = dag_name

    success_run = True

    try:
        logger.info("m=__main__, msg=Checking which gsheet has to be ingested...")
        recently_modified_gsheets_ids = gsheets_service.get_recently_modified_gsheet(
            drive_service
        )
        import_range_gsheets_ids = gsheets_service.get_gsheets_with_import_range(
            gsheets_client=gsheets_client, all_sheets_dict=sheet_details_dict
        )

        recently_modified_gsheets_ids_list = [
            sheet_id for sheet_id in recently_modified_gsheets_ids
        ]
        ids_to_be_ingested_list = (
            recently_modified_gsheets_ids_list + import_range_gsheets_ids
        )

        for raw_table_name, sheet_info in sheet_details.items():
            sheet_id = sheet_info["sheet_id"]
            if sheet_id in ids_to_be_ingested_list:
                sheets_to_be_ingested.append(
                    sheet_info["clean_table_name"]
                )  # The DAG Builder actually uses the clean table name to attach raw and clean tasks together

        logger.debug(
            f"m=__main__, msg=Found {len(sheets_to_be_ingested)} gsheets to be ingested"
        )
    except Exception as e:
        success_run = False
        logger.error(f"m=__main__, msg=An exception occurred: {repr(e)}")
    finally:
        output_json = {
            "success_run": success_run,
            "sheets_to_be_ingested": sheets_to_be_ingested,
        }
        dbutils.notebook.exit(json.dumps(output_json))
