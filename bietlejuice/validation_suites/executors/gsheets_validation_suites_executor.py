from typing import Any, List, Dict, Union, Tuple

from datetime import datetime, timedelta
import pendulum
import re
from unidecode import unidecode

from pyspark.sql import functions
from pyspark.sql.types import StructField, StructType, StringType
from quintoandar_gsheets_api_client import GoogleSheetsClient
from quintoandar_logger import QuintoAndarLogger
from validations_engine.base_validation_suites_executor import (
    BaseValidationSuitesExecutor,
)

from bietlejuice.base import DATALAKE_SQL_DIR
from bietlejuice.base.api import APIEnum
from bietlejuice.base.notification import SLACK_USER_GROUPS_MAPPING_PATH
from bietlejuice.base.spark import SparkDataFrameService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import DatabricksConsumer
from bietlejuice.services import FileService

from googleapiclient.discovery import build
from google.oauth2.service_account import Credentials

logger = QuintoAndarLogger("GsheetsValidationSuitesExecutor")


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
    ]

    def __init__(self, auth):
        super().__init__(auth)
        self.auth = auth
        self.credentials, self.scope = self.get_credentials_and_scope()
        self.drive_service = self.build_drive_api_service()

        self.delta = self.get_recently_modified_gsheet(self.drive_service)
        self.context_slack_owner_dict = FileService.get_dict_from_yaml_file(
            SLACK_USER_GROUPS_MAPPING_PATH
        )

    def __generate_schema(self, data: Union[List[Dict], List], sheet_name: str):
        """
        Generates the schema using the gsheet's columns names.

        Build the schema for this gsheet and defines all the columns types
        as strings for the temporary table load.
        """
        if len(data):
            columns = data[0].keys()
            type_array = [
                StructField(column_name, StringType()) for column_name in columns
            ]
            schema = StructType(type_array)
            return schema

        raise ValueError(f"m=__generate_schema, msg=Table {sheet_name} Empty!")

    def _get_slack_group_from_context(self, context_name: str):
        return self.context_slack_owner_dict.get(context_name)

    def get_credentials_and_scope(self) -> Tuple[dict, str]:
        credentials = self.auth[APIEnum.GSHEETS_CREDENTIALS]
        scope = credentials.get("scope")

        return credentials, scope

    def get_gsheets_client(self) -> GoogleSheetsClient:
        gsheet_client = self.REPOSITORY_CONSUMER_CLASS(self.credentials, self.scope)

        return gsheet_client

    def build_scoped_credentials(self) -> Credentials:
        credential = Credentials.from_service_account_info(self.credentials)
        scoped_credentials = credential.with_scopes(self.EXTRA_SCOPES)

        return scoped_credentials

    def build_drive_api_service(self) -> Any:
        scoped_credentials = self.build_scoped_credentials()
        drive_service = build("drive", "v3", credentials=scoped_credentials)
        return drive_service

    def load_gsheet_on_temp_view(
        self, data: Union[List[Dict], List], clean_table_name: str, is_partitioned: bool
    ):
        """
        Load the data from API into a temporary view.

        :return: Temporary view from each gsheet.
        """
        spark_client = SparkClient()
        schema = self.__generate_schema(data, clean_table_name)
        df = spark_client.create_dataframe(data, schema=schema)
        df = df.withColumn("ts_load", functions.current_timestamp())
        if is_partitioned:
            df = (
                SparkDataFrameService()
                .input(df)
                .create_year_month_day_columns_from_dataframe_column("ts_load")
                .output()
            )
        df = self.__columns_to_snake_case(df)

        return df.createTempView(f"{self.TEMPORARY_TABLE_PREFIX}{clean_table_name}")

    def run_and_validate_clean_query(
        self, gsheets_context: str, clean_table_name: str, raw_table_name: str
    ) -> None:
        """
        Loads clean table from path and tries to run it in the previously
         created temp table.

        :return: True if the validation succeeded. Else an error is raised.
        """
        clean_query = self.load_clean_query(gsheets_context, clean_table_name)
        clean_query = self.swap_raw_table_with_temporary(
            raw_table_name, clean_table_name, clean_query
        )
        self.try_run_clean_query_into_table(clean_query)

    @staticmethod
    def load_clean_query(gsheets_context: str, clean_table_name: str) -> str:
        context_level = f"{gsheets_context}/" if gsheets_context else ""
        query_path = f"{DATALAKE_SQL_DIR}/queries/gsheets/clean/{context_level}{clean_table_name}.sql"
        query_content = FileService.get_query_from_file_name(query_path)

        return query_content

    def swap_raw_table_with_temporary(
        self, raw_table_name: str, tmp_table_name: str, clean_query: str
    ) -> str:
        raw_table = f"{self.GSHEETS_DATA_LAKE_RAW_SCHEMA}.{raw_table_name}"
        tmp_table = f"{self.TEMPORARY_TABLE_PREFIX}{tmp_table_name}"

        return clean_query.replace(raw_table, tmp_table)

    def try_run_clean_query_into_table(self, clean_query: str) -> None:
        """
        Try to run the clean query on sheet temp raw table.
        If it succeeds, the data is returned. If it fails, an exception is
         raised and caught by validator engine.

        :param clean_query: the clean SparkSQL
        :return: cleaned data
        """
        databricks_consumer = DatabricksConsumer(
            conn_config={"db": self.GSHEETS_DATA_LAKE_CLEAN_SCHEMA},
            spark_client=SparkClient(),
        )
        databricks_consumer.get_data_from_query(clean_query)

    def get_recently_modified_gsheet(self, drive_service) -> List:
        """
        Get the sheet ids for the Gsheets modified until the DAG run.

        This method won't use the GoogleSheetClient. Needs a better understanding
        on how to fit inside this class, maybe some more methods will be developed.

        :returns: A list of spreadsheet_ids (strings)
        """
        files = {}
        page_token = None
        time_zone = pendulum.timezone("America/Sao_Paulo")
        execution_time = datetime.now(tz=time_zone) - timedelta(hours=24)
        query = f"mimeType='application/vnd.google-apps.spreadsheet' and modifiedTime > '{execution_time.isoformat()}'"

        while True:
            response = (
                drive_service.files()
                .list(
                    q=query,
                    spaces="drive",
                    fields="nextPageToken, files(id, modifiedTime, lastModifyingUser(displayName, emailAddress))",
                    supportsAllDrives=True,
                    includeItemsFromAllDrives=True,
                    pageToken=page_token,
                )
                .execute()
            )

            for file in response.get("files", []):
                files.update(
                    {
                        file.get("id"): {
                            "modified_time": file.get("modifiedTime"),
                            "modifier_user_email": file.get(
                                "lastModifyingUser", {}
                            ).get("emailAddress", "User email unkown"),
                            "modifier_user_name": file.get("lastModifyingUser", {}).get(
                                "displayName", "User name unkown"
                            ),
                        }
                    }
                )

            page_token = response.get("nextPageToken", None)
            if page_token is None:
                break

        return files

    def append_validations_for_each_sheet(self, gsheets_files_path: str) -> None:
        """
        Creates a validation method for each sheet mapped in the gsheets_files.yaml

        Because each method validation_*() is executed independently by the engine, if one
         breaks, the other validation will not be affected and will be executed in sequence.
        Thus, since we want to create validations for each sheet automatically, we need to
         create a validation method for each one in execution time.

        :param gsheets_files_path: the path of yaml with gsheets to be read
        """
        all_sheets = FileService.get_dict_from_yaml_file(gsheets_files_path)

        # if not self.delta: maybe validate if there is any spreadsheet to validate before running.
        #     return
        for raw_table_name, sheet in all_sheets.items():
            sheet["raw_table_name"] = raw_table_name
            if sheet["sheet_id"] in self.delta:
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

    def __format_column_name(self, column_name):
        alphanumeric_column_name = re.sub(r"[^\w\s]", "", column_name)
        snake_cased_column_name = re.sub(r"\s+", "_", alphanumeric_column_name)
        no_accents_column_name = unidecode(snake_cased_column_name)
        return no_accents_column_name.lower()

    def __columns_to_snake_case(self, df):
        old_columns = df.columns
        new_columns = [self.__format_column_name(column) for column in old_columns]
        return df.toDF(*new_columns)

    def _run_sheet_validation(
        self,
        sheet_id: str,
        sheet_name: str,
        gsheets_context: str,
        clean_table_name: str,
        raw_table_name: str,
        is_partitioned: bool = False,
    ) -> None:
        gsheet_client = self.get_gsheets_client()
        data = gsheet_client.get_data_from_sheet(sheet_name, sheet_id)
        self.load_gsheet_on_temp_view(data, clean_table_name, is_partitioned)
        self.run_and_validate_clean_query(
            gsheets_context, clean_table_name, raw_table_name
        )
