import gc
import logging
import os
import re
import time
from datetime import datetime, timedelta
from typing import List, Union, Dict

from gspread.exceptions import SpreadsheetNotFound, WorksheetNotFound

import pendulum
from pyspark.sql import DataFrame
from quintoandar_gsheets_api_client import GoogleSheetsClient
from quintoandar_gsheets_api_client.consumer import GoogleSheetsReader
from quintoandar_gsheets_api_client.exceptions.exceptions import (
    PermissionException,
    EntityNotFoundException,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import DatabricksConsumer
from dags import DAG_PACKAGES_ROOT

JOB_NAME = "gsheets_service"

logging.getLogger("py4j").setLevel(logging.INFO)
logger = QuintoAndarLogger(JOB_NAME)


DEPS_YAML_PATH = os.path.join(DAG_PACKAGES_ROOT, "dependencies.yaml")
GSHEETS_DATALAKE_RAW_SCHEMA = "datalake_{schema}_raw"
GSHEETS_DATALAKE_CLEAN_SCHEMA = "datalake_{schema}_clean"


class GsheetsService:
    TEMPORARY_TABLE_PREFIX = "temp_"

    def __init__(self, schema="gsheets"):
        self.gsheets_datalake_raw_schema = GSHEETS_DATALAKE_RAW_SCHEMA.format(
            schema=schema
        )
        self.gsheets_data_lake_clean_schema = GSHEETS_DATALAKE_CLEAN_SCHEMA.format(
            schema=schema
        )

    def get_recently_modified_gsheet(self, drive_service) -> Dict:
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
        file_info_fields = [
            "id",
            "modifiedTime",
            "lastModifyingUser(displayName, emailAddress)",
            "sharingUser(displayName, emailAddress)",
        ]
        fields = f"nextPageToken, files({', '.join(file_info_fields)})"

        while True:
            response = (
                drive_service.files()
                .list(
                    q=query,
                    spaces="drive",
                    fields=fields,
                    supportsAllDrives=True,
                    includeItemsFromAllDrives=True,
                    pageToken=page_token,
                    corpora="allDrives",
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
                            ).get("emailAddress", "Last modifying user email unknown"),
                            "modifier_user_name": file.get("lastModifyingUser", {}).get(
                                "displayName", "Last modifying user name unknown"
                            ),
                            "sharing_user_name": file.get("sharingUser", {}).get(
                                "displayName", "Sharing user name unknown"
                            ),
                            "sharing_user_email": file.get("sharingUser", {}).get(
                                "emailAddress", "Sharing user email unknown"
                            ),
                        }
                    }
                )

            page_token = response.get("nextPageToken", None)
            if page_token is None:
                break

        return files

    @staticmethod
    def __has_import_range(sheet_data: list) -> bool:
        regex_pattern = re.compile("IMPORTRANGE", re.IGNORECASE)
        for row in sheet_data:
            for column_value in row:
                if re.search(regex_pattern, str(column_value)) is not None:
                    return True
        return False

    def get_gsheets_with_import_range(
        self, gsheets_client: GoogleSheetsClient, all_sheets_dict: dict
    ) -> List:
        gsheets_consumer = GoogleSheetsReader(google_sheets_client=gsheets_client)
        logger.info(
            "m=get_gsheets_with_import_range, msg=Started checking all sheets for IMPORTRANGE presence"
        )
        import_range_sheets_ids = []
        gsheets_count = 0

        for raw_table_name, sheet in all_sheets_dict.items():

            if gsheets_count == 90:  # Current quota = 600. Each call makes 3 requests.
                gsheets_count = 0
                time.sleep(60)  # Time to reset the quota
            sheet_id = sheet["sheet_id"]
            sheet_name = sheet["sheet_name"]

            if sheet.get("sheet_context") == "static" or sheet["dag_name"] in (
                "gsheets_people",
                "gsheets_people_pin",
                "gsheets_people_static",
            ):
                continue
            try:
                sheet_data = gsheets_consumer.read_sheet_rows(
                    sheet_id=sheet_id,
                    sheet_name=sheet_name,
                    value_render_option="FORMULA",
                )

                if (
                    self.__has_import_range(sheet_data)
                    and sheet_id not in import_range_sheets_ids
                ):
                    import_range_sheets_ids.append(sheet_id)
            except WorksheetNotFound as e:
                logger.error(
                    f"m=get_gsheets_with_import_range, msg=spreadsheet {raw_table_name} not found, e={e}"
                )
            except (SpreadsheetNotFound, EntityNotFoundException) as e:
                logger.error(
                    f"m=get_gsheets_with_import_range, msg=sheet {sheet_name} not found, e={e}"
                )
                import_range_sheets_ids.append(sheet_id)
                # We have to add it here, so it get validated later, otherwise it won't be validated because it won't be
                # found since the service account has no permission to access it.
            except PermissionException as e:
                logger.error(
                    f"m=get_gsheets_with_import_range, msg=Caller has no permission on {sheet_name} , e={e}"
                )
                import_range_sheets_ids.append(sheet_id)
                # We have to add it here, so it get validated later, otherwise it won't be validated because it won't be
                # found since the service account has no permission to access it.
            gsheets_count += 1

        logger.info("m=get_gsheets_with_import_range, msg=Finished executing")
        return import_range_sheets_ids

    @staticmethod
    def load_clean_query(clean_table_name: str, dag_name: str) -> str:
        """
        :param dag_name: The DAG (Package) name
        :param clean_table_name: Table name for sheet on clean layer
        """

        query_content = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
            dag_name=dag_name, table_name=clean_table_name, layer="clean"
        )
        return query_content

    def swap_raw_table_with_temporary(
        self, raw_table_name: str, tmp_table_name: str, clean_query: str
    ) -> str:
        """
        :param raw_table_name: Table name for sheet on raw layer
        :param tmp_table_name: Table name for sheet on temporary table
        :param clean_query: SQL query for clean layer
        """
        raw_table = f"{self.gsheets_datalake_raw_schema}.{raw_table_name}"
        tmp_table = f"{self.TEMPORARY_TABLE_PREFIX}{tmp_table_name}"

        return clean_query.replace(raw_table, tmp_table)

    def try_run_clean_query_into_table(
        self, spark_client: SparkClient, clean_query: str
    ) -> None:
        """
        Try to run the clean query on sheet temp raw table.
        If it succeeds, the data is returned. If it fails, an exception is
         raised and caught by validator engine.

        :param spark_client: A client to handle the Spark connection
        :param clean_query: SQL query for clean layer
        """
        databricks_consumer = DatabricksConsumer(
            conn_config={"db": self.gsheets_data_lake_clean_schema},
            spark_client=spark_client,
        )
        databricks_consumer.get_data_from_query(clean_query)

    def run_and_validate_clean_query(
        self,
        dag_name,
        spark_client: SparkClient,
        clean_table_name: str,
        raw_table_name: str,
    ) -> Union[bool, None]:
        """
        Loads clean table from path and tries to run it in the previously
         created temp table.
        :param dag_name: Used to find the query file according to the DAG Package
        :param spark_client: A client to handle the Spark connection
        :param clean_table_name: Table name for sheet on clean layer
        :param raw_table_name: Table name for sheet on raw layer

        Returns True if the validation succeeded. Else an error is raised.
        """
        clean_query = self.load_clean_query(clean_table_name, dag_name)
        clean_query = self.swap_raw_table_with_temporary(
            raw_table_name, clean_table_name, clean_query
        )
        self.try_run_clean_query_into_table(spark_client, clean_query)
        return True

    def release_memory(
        self, spark_client: SparkClient, dataframe: DataFrame, clean_table_name: str
    ) -> None:
        """
        Drops temp table, JVM dataframe and python runtime variables to release cluster memory
        :param spark_client: A client to handle the Spark connection
        :param dataframe: Spark Dataframe with Google sheets data.
        :param clean_table_name: Table name for sheet on clean layer
        """
        spark_client.conn.catalog.dropTempView(
            f"{self.TEMPORARY_TABLE_PREFIX}{clean_table_name}"
        )
        dataframe.unpersist(blocking=True)
        del dataframe
        gc.collect()

    def validate_clean_query_against_raw(
        self,
        dag_name,
        spark_client: SparkClient,
        df: DataFrame,
        raw_table_name: str,
        clean_table_name: str,
    ) -> None:
        """
        Loads raw Dataframe into a temporary view and validates clean query against it
        :param dag_name: Used to find the query file according to the DAG Package
        :param spark_client: A client to handle the Spark connection
        :param df: Spark Dataframe with Google sheets data
        :param raw_table_name: Table name for sheet on raw layer
        :param clean_table_name: Table name for sheet on clean layer
        """

        df.createTempView(f"{self.TEMPORARY_TABLE_PREFIX}{clean_table_name}")
        self.run_and_validate_clean_query(
            dag_name, spark_client, clean_table_name, raw_table_name
        )
        self.release_memory(spark_client, df, clean_table_name)

    def clean_unsupported_column_names(self, df: DataFrame) -> DataFrame:
        """
        Cleans unsupported column names from a DataFrame
        Unity catalog does not support column names with 0 length or greater than 255 characters
        :param df: Spark Dataframe with Google sheets data
        :return: Spark Dataframe with cleaned column names
        """
        for column in df.columns:
            if column == "":
                df = df.withColumnRenamed(column, "unnamed_column")
            if len(column) > 255:
                df = df.withColumnRenamed(column, column[:255])
        return df
