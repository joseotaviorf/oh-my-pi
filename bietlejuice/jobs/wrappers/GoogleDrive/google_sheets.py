import re

import petl
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
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
    def move_sheets_data_to_destination(self, google_sheets_files, enumdb_destination):
        if not google_sheets_files:
            raise ValueError(
                'm=move_sheets_data_to_destination, msg=no files set.')

        gsheets = GoogleSheetsClient(self.google_s_a_credentials, self.google_api_scope)

        for item in google_sheets_files:
            df_gsheets = gsheets.get_dataframe_from_sheet(sheet_name=item['sheetName'],
                                                          sheet_id=item['sheetId'])
            if df_gsheets is None:
                raise ValueError(
                    "m=move_sheets_data_to_destination, sheet_id={}, sheet_name={}, "
                    "msg=no data found in google sheets.".format(
                        item['sheetId'], item['sheetName']))

            snake_case_columns = self._to_snake_case_columns(df_gsheets.columns)
            df_gsheets.rename(columns=snake_case_columns, inplace=True)

            if enumdb_destination == EnumDB.QuintoAndar_datalake:
                self._move_df_to_datalake(df=df_gsheets, table_name=item['s3_path'])
            if enumdb_destination == EnumDB.BI_ODS:
                self._move_df_to_ods(df=df_gsheets, table_name=item['s3_path'], schema='files')

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

    @logger(exclude='df')
    def _move_df_to_datalake(self, df, table_name):
        s3 = S3ToODS(s3_bucket=self.s3_bucket)
        logger.info('m=_move_df_to_datalake, table_name={0}, msg=Sending df to datalake'.format(table_name))
        s3.move_df_to_datalake(df=df, tablename=table_name)

    @logger(exclude='df')
    def _move_df_to_ods(self, df, table_name, schema):
        exists = BaseETL.table_exists(
            db_enum=EnumDB.BI_ODS,
            table_name=table_name,
            schema=schema
        )
        if not exists:
            logger.info('m=_move_df_to_ods, table_name={0}, schema={1}, msg=Creating table'.format(table_name, schema))
            BaseETL.create_table(
                conn=BaseETL.get_connection(db_enum=EnumDB.BI_ODS),
                table=petl.fromdataframe(df),
                tablename=table_name,
                schema=schema
            )

        logger.info('m=_move_df_to_ods, table_name={0},schema={1}, msg=Sending df to ods'.format(table_name, schema))
        try:
            BaseETL.dataframe_to_ods(
                df=df,
                table_name='{}."{}"'.format(schema, table_name),
                append=False,
                encoding='utf-8'
            )
        except Exception as e:
            raise RuntimeError('m=_move_df_to_ods, table_name={0}, schema={1}, error={2}, '
                               'msg=Problem in send df to ods'.format(table_name, schema, str(e.message)))
