from glob import glob

from pyspark.sql.utils import AnalysisException
from gspread.exceptions import SpreadsheetNotFound, WorksheetNotFound

from quintoandar_gsheets_api_client.clients import GoogleSheetsClient
from quintoandar_logger import QuintoAndarLogger
from quintoandar_gsheets_api_client.exceptions.exceptions import (
    QuotaExceededException,
    EntityNotFoundException,
    ServiceUnavailableException,
    InternalErrorException,
    PermissionException,
)
from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum
from dags import DAG_PACKAGES_ROOT
from bietlejuice.validation_suites.executors.gsheets_validation_suites_executor import (
    GsheetsValidationSuitesExecutor,
)

logger = QuintoAndarLogger("GSheetsByContextValidationSuite")


class GSheetsByContextValidationSuite(GsheetsValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = GoogleSheetsClient

    GSHEETS_BASE_URL = "https://docs.google.com/spreadsheets/d/"
    SLACK_MSG_TEMPLATE = """
    :sheets: Sheet: <{sheet_url}|{sheet_name}> (ID: {sheet_id})
    *Last modifier*: {mod_user_name} - <@{mod_user_slack}> - {mod_user_email}.
    *Sharing user*: {sharing_user_name} - <@{sharing_user_slack}> - {sharing_user_email}.
    *Owner team*: {context_owner}
    Error: {error_message}
    ```{error_trace}```
    """
    SLACK_SMALL_TEMPLATE = """
    :sheets: Sheet: <{sheet_url}|{sheet_name}> (ID: {sheet_id})
    *Owner team*: {context_owner}
    Error: {error_message}
    ```{error_trace}```
    """

    def __init__(self, auth) -> None:

        gsheets_dags_glob_path = DAG_PACKAGES_ROOT + "/*/gsheets_*"
        dags = glob(pathname=gsheets_dags_glob_path, recursive=True)

        logger.info(
            f"m=GSheetsByContextValidationSuite, msg= gsheets_dags_glob_path: {gsheets_dags_glob_path}, dags: {dags}"
        )

        super().__init__(auth, dags)
        self.append_validations_for_each_sheet()
        self.SLACK_CHANNEL = auth[SlackWebhooksEnum.DATA_ALERTS]
        self.SLACK_MSG_HEADER = (
            ":alert: *Gsheet validations failures*\n"
            ">The following sheets have errors and will not be ingested on the next pipeline run if the issues are not resolved."
        )

    def _validate_sheet(self, _sheet_info: dict) -> None:
        """
        Main validation method of the sheets.
        Will be called by the lambda associated to each sheet's method.

        :param: _sheet_info: sheet dict with its info.
        """
        sheet_url = f"{self.GSHEETS_BASE_URL}{_sheet_info['sheet_id']}"
        context = _sheet_info.get("dag_name")
        context_owner = self._get_slack_group_from_context(context)
        try:
            self._run_sheet_validation(
                dag_name=_sheet_info["dag_name"],
                sheet_id=_sheet_info["sheet_id"],
                sheet_name=_sheet_info["sheet_name"],
                clean_table_name=_sheet_info.get("clean_table_name"),
                raw_table_name=_sheet_info.get("raw_table_name"),
                is_partitioned=_sheet_info.get("partitioned", False),
                preload_time_in_seconds=_sheet_info.get(
                    "preload_time_in_seconds", None
                ),
            )
        except (
            AnalysisException,
            QuotaExceededException,
            ServiceUnavailableException,
            InternalErrorException,
            WorksheetNotFound,
        ) as e:
            sheet_modification_info = self.delta.get(_sheet_info["sheet_id"])
            error_trace = str(e).split("\n")[0].replace("`", "")
            error_trace = error_trace.replace('"', "")[slice(0, 150)]
            error_message = e.__doc__
            self.SLACK_MSG = self.SLACK_MSG_TEMPLATE.format(
                sheet_url=sheet_url,
                sheet_name=_sheet_info.get("sheet_name"),
                sheet_id=_sheet_info["sheet_id"],
                mod_user_name=sheet_modification_info.get("modifier_user_name"),
                mod_user_slack=sheet_modification_info.get("modifier_user_email").split(
                    "@"
                )[0],
                mod_user_email=sheet_modification_info.get("modifier_user_email"),
                sharing_user_name=sheet_modification_info.get("sharing_user_name"),
                sharing_user_slack=sheet_modification_info.get(
                    "sharing_user_email"
                ).split("@")[0],
                sharing_user_email=sheet_modification_info.get("sharing_user_email"),
                context_owner=context_owner,
                error_message=error_message,
                error_trace=error_trace,
            )
            raise e
        except (PermissionException, EntityNotFoundException, SpreadsheetNotFound) as e:
            error_trace = str(e).split("\n")[0].replace("`", "")
            error_trace = error_trace.replace('"', "")[slice(0, 150)]
            error_message = e.__doc__
            self.SLACK_MSG = self.SLACK_SMALL_TEMPLATE.format(
                sheet_url=sheet_url,
                sheet_name=_sheet_info.get("sheet_name"),
                sheet_id=_sheet_info["sheet_id"],
                context_owner=context_owner,
                error_message=error_message,
                error_trace=error_trace,
            )
            raise e
        except Exception as e:
            # Added this broad exception to notify unexpected cases.
            error_trace = str(e).split("\n")[0].replace("`", "")
            error_trace = error_trace.replace('"', "")[slice(0, 150)]
            error_message = e.__doc__
            self.SLACK_MSG = self.SLACK_SMALL_TEMPLATE.format(
                sheet_url=sheet_url,
                sheet_name=_sheet_info.get("sheet_name"),
                sheet_id=_sheet_info["sheet_id"],
                context_owner=context_owner,
                error_message=error_message,
                error_trace=error_trace,
            )
            raise e
