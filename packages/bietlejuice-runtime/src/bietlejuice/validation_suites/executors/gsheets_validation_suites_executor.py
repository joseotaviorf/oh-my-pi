from typing import Any, List, Tuple, Union

from google.oauth2.service_account import Credentials
from googleapiclient.discovery import build
from quintoandar_gsheets_api_client import GoogleSheetsClient
from quintoandar_logger import QuintoAndarLogger
from validations_engine.base_validation_suites_executor import (
    BaseValidationSuitesExecutor,
)

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.api_consumers.gsheets_consumer import GsheetsConsumer
from bietlejuice.services.configuration_service import ConfigurationService
from bietlejuice.services.gsheets_service import GsheetsService

logger = QuintoAndarLogger("GsheetsValidationSuitesExecutor")
TIMEOUT_LIMIT = 3 * 60


class GsheetsValidationSuitesExecutor(BaseValidationSuitesExecutor):
    """
    Gsheets Validations Executor
    This executor runs default validations (defined in this class) and custom
    validations (defined in each heir class).
    """

    GSHEETS_DATA_LAKE_RAW_SCHEMA = "datalake_gsheets_raw"
    GSHEETS_DATA_LAKE_CLEAN_SCHEMA = "datalake_gsheets_clean"
    TEMPORARY_TABLE_PREFIX = "temp_"

    EXTRA_SCOPES = [
        "https://www.googleapis.com/auth/spreadsheets.readonly",
        "https://www.googleapis.com/auth/drive.readonly",
        "https://www.googleapis.com/auth/drive",
        "https://www.googleapis.com/auth/drive.appdata",
        "https://www.googleapis.com/auth/drive.file",
        "https://www.googleapis.com/auth/drive.metadata",
        "https://www.googleapis.com/auth/drive.metadata.readonly",
    ]

    def __init__(self, auth, dags: List):
        super().__init__(auth)
        self.auth = auth
        self.dags = dags

        self.credentials, self.scope = self.get_credentials_and_scope()
        self.drive_service = self.build_drive_api_service()
        self.gsheets_service = GsheetsService()
        self.spark_client = SparkClient()

        self.all_sheets = self.get_all_sheets_info()
        self.delta = self.gsheets_service.get_recently_modified_gsheet(
            self.drive_service
        )

    def get_all_sheets_info(self):
        sheets_info = {}
        for file_path in self.dags:
            dag_name = file_path.split("/")[-1]
            config_service = ConfigurationService(dag_name)
            context_sheets_info = config_service.get_config("sheets_info")
            context_sheets_info_completed = {
                raw_sheet_name: {**sheet_info, "dag_name": dag_name}
                for raw_sheet_name, sheet_info in context_sheets_info.items()
            }
            sheets_info.update(context_sheets_info_completed)
        return sheets_info

    def get_credentials_and_scope(self) -> Tuple[dict, str]:
        credentials = self.auth[APIEnum.GSHEETS_CREDENTIALS]
        scope = credentials.get("scope")

        return credentials, scope

    def get_gsheet_client(self, custom_timeout=None) -> GoogleSheetsClient:
        timeout = custom_timeout if custom_timeout is not None else TIMEOUT_LIMIT
        gsheet_client = self.REPOSITORY_CONSUMER_CLASS(
            self.credentials, self.scope, timeout=timeout
        )

        return gsheet_client

    def build_scoped_credentials(self) -> Credentials:
        credential = Credentials.from_service_account_info(self.credentials)
        scoped_credentials = credential.with_scopes(self.EXTRA_SCOPES)

        return scoped_credentials

    def build_drive_api_service(self) -> Any:
        scoped_credentials = self.build_scoped_credentials()
        drive_service = build("drive", "v3", credentials=scoped_credentials)
        return drive_service

    def append_validations_for_each_sheet(self) -> None:
        """
        Creates a validation method for each sheet mapped in the gsheets_files.yaml

        Because each method validation_*() is executed independently by the engine, if one
         breaks, the other validation will not be affected and will be executed in sequence.
        Thus, since we want to create validations for each sheet automatically, we need to
         create a validation method for each one in execution time.

        :param gsheets_files_path: the path of yaml with gsheets to be read
        """
        import_range_gsheets = self.gsheets_service.get_gsheets_with_import_range(
            self.get_gsheet_client(5 * 60), self.all_sheets
        )

        for raw_table_name, sheet in self.all_sheets.items():
            sheet["raw_table_name"] = raw_table_name
            sheet_id = sheet["sheet_id"]

            if sheet_id in self.delta or sheet_id in import_range_gsheets:
                validate_sheet_method_name = (
                    f'validate_sheet_{str(sheet["clean_table_name"]).lower()}'
                )

                # The method validate_sheet_<sheet_name> will be called by the self.run() method.
                # The default values of the lambda sends/binds the sheet id and name to the validation method
                setattr(
                    self.__class__,
                    validate_sheet_method_name,
                    lambda _self, _sheet_info=sheet: _self._validate_sheet(_sheet_info),
                )

    def _run_sheet_validation(
        self,
        dag_name: str,
        sheet_id: str,
        sheet_name: str,
        clean_table_name: str,
        raw_table_name: str,
        is_partitioned: bool = False,
        preload_time_in_seconds: Union[int, None] = None,
    ) -> None:
        gsheets_client = self.get_gsheet_client()
        gsheets_consumer = GsheetsConsumer(gsheets_client, self.spark_client)

        df = gsheets_consumer.get_sheet_df(
            sheet_name,
            sheet_id,
            clean_table_name,
            is_partitioned,
            preload_time_in_seconds,
        )

        self.gsheets_service.validate_clean_query_against_raw(
            dag_name, self.spark_client, df, raw_table_name, clean_table_name
        )
