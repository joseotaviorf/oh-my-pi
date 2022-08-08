from quintoandar_gsheets_api_client.clients import GoogleSheetsClient

from bietlejuice.base.validation_suites.executors.gsheets_validation_suites_executor import (
    GsheetsValidationSuitesExecutor,
)
from bietlejuice.dags import COMPOSER_DAGS_PATH


class GSheetsByContextValidationSuite(GsheetsValidationSuitesExecutor):
    REPOSITORY_CONSUMER_CLASS = GoogleSheetsClient
    GSHEETS_FILES_PATH = COMPOSER_DAGS_PATH + "/gsheets_by_context/gsheets_files.yaml"

    def __init__(self, auth) -> None:
        super().__init__(auth)
        self.append_validations_for_each_sheet(self.GSHEETS_FILES_PATH)

    def _validate_sheet(self, _sheet_info: dict) -> None:
        """
        Main validation method of the sheets.
        Will be called by the lambda associated to each sheet's method.

        :param sheet_id: the sheet id, got via lambda default value
        :param sheet_name: the sheet name, got via lambda default value
        """
        self._run_sheet_validation(
            _sheet_info["sheet_id"],
            _sheet_info["sheet_name"],
            _sheet_info.get("sheet_context"),
            _sheet_info.get("clean_table_name"),
        )
