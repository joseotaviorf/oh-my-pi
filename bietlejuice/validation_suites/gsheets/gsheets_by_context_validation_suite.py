from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from bietlejuice.base.validation_suites.executors.gsheets_validation_suites_executor import (
    GsheetsValidationSuitesExecutor,
)
from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum
from bietlejuice.dags import COMPOSER_DAGS_PATH

from pyspark.sql.utils import AnalysisException


class GSheetsByContextValidationSuite(GsheetsValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = GoogleSheetsClient
    GSHEETS_FILES_PATH = COMPOSER_DAGS_PATH + "/gsheets_by_context/gsheets_files.yaml"
    SLACK_MSG_TEMPLATE = """:sheets: Sheet: <{}|{}> (ID:{})\n\t_Last modifier: {} - <@{}> - {}. Owner team: {}._\n\tError: ```{}```"""
    SLACK_MSG_TEMPLATE_SMALL = """:sheets: Sheet: <{}|{}> (ID:{})\n. Owner team: {}._\n\tError: *Other related errors, please contact the Analytics Engineering owner team.*"""

    def __init__(self, auth) -> None:
        super().__init__(auth)
        self.append_validations_for_each_sheet(self.GSHEETS_FILES_PATH)
        self.SLACK_CHANNEL = auth[SlackWebhooksEnum.DATA_ALERTS]
        self.SLACK_MSG_HEADER = ":alert: *Gsheet validations failures*\n>_The following sheets have errors and will not be ingested on the next pipeline run if the issues are not resolved._"

    def _validate_sheet(self, _sheet_info: dict) -> None:
        """
        Main validation method of the sheets.
        Will be called by the lambda associated to each sheet's method.

        :param sheet_id: the sheet id, got via lambda default value
        :param sheet_name: the sheet name, got via lambda default value
        """
        try:
            self._run_sheet_validation(
                _sheet_info["sheet_id"],
                _sheet_info["sheet_name"],
                _sheet_info.get("sheet_context"),
                _sheet_info.get("clean_table_name"),
                _sheet_info.get("raw_table_name"),
            )
        except Exception as e:
            sheet_info = self.delta.get(_sheet_info["sheet_id"])
            sheet_url = (
                f"https://docs.google.com/spreadsheets/d/{_sheet_info['sheet_id']}"
            )

            context = _sheet_info.get("sheet_context").replace("_intraday", "")
            context_owner = self._get_slack_group_from_context(context)

            if e.__class__ == AnalysisException:
                self.SLACK_MSG = self.SLACK_MSG_TEMPLATE.format(
                    sheet_url,
                    _sheet_info.get("sheet_name"),
                    _sheet_info["sheet_id"],
                    sheet_info.get("modifier_user_name"),
                    sheet_info.get("modifier_user_email").split("@")[0],
                    sheet_info.get("modifier_user_email"),
                    context_owner,
                    str(e).split("\n")[0].replace("`", ""),
                )
            else:
                self.SLACK_MSG = self.SLACK_MSG_TEMPLATE_SMALL.format(
                    sheet_url,
                    _sheet_info.get("sheet_name"),
                    _sheet_info["sheet_id"],
                    context_owner,
                )
            raise e
