import re

from bietlejuice.jobs.etl.s3_files_to_ods import S3ToODS
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.google.google_sheets import GoogleSheetsClient

logger = QuintoAndarLogger('GoogleSheets')


class GoogleSheets(object):
    def __init__(self, s3_bucket, google_s_a_credentials, google_api_scope):
        self.s3_bucket = s3_bucket
        self.google_s_a_credentials = google_s_a_credentials
        self.google_api_scope = google_api_scope

    @logger(exclude=['google_sheets_files'])
    def move_sheets_data_to_datalake(self, google_sheets_files):
        if not google_sheets_files['files']:
            raise ValueError(
                'm=move_sheets_data_to_datalake, msg=no files set in json google sheets schema.')

        gsheets = GoogleSheetsClient(self.google_s_a_credentials, self.google_api_scope)
        s3 = S3ToODS(s3_bucket=self.s3_bucket)

        for item in google_sheets_files['files']:
            df_gsheets = gsheets.get_dataframe_from_sheet(sheet_name=item['sheetName'],
                                                          sheet_id=item['sheetId'])
            if df_gsheets is None:
                raise ValueError(
                    'm=move_sheets_data_to_datalake, file={}, msg=no data found in google sheets.'.format(item))

            snake_case_columns = self._to_snake_case_columns(df_gsheets.columns)
            df_gsheets.rename(columns=snake_case_columns, inplace=True)
            s3.move_df_to_datalake(df=df_gsheets, tablename=item['s3_path'])

    @staticmethod
    @logger(exclude='old_columns')
    def _to_snake_case_columns(old_columns):
        _underscorer1 = re.compile(r'(\S)([A-Z][a-z]+)')
        _underscorer2 = re.compile('([a-z0-9])([A-Z])')

        new_columns = {}

        for old_column in old_columns:
            subbed = _underscorer1.sub(r'\1_\2', old_column)
            new_column = _underscorer2.sub(r'\1_\2', subbed).lower()
            new_column = new_column.replace(' ', '_')
            new_columns.update({old_column: new_column})

        return new_columns
