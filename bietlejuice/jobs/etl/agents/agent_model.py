import re
import os
from datetime import datetime

import petl
from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.google.google_sheets import GoogleSheetsClient

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDB
from bietlejuice.jobs.etl import SOURCE_QUERIES_DIR, DW_QUERIES_DIR, ODS_QUERIES_DIR, DATALAKE_QUERIES_DIR
from bietlejuice.jobs.etl.s3_files_to_ods import S3ToODS

logger = QuintoAndarLogger('Agent')


class Agent(object):
    def __init__(self, bucket_name):
        self.bucket_datalake = bucket_name

    def _format_query_filename(self, filename, db_enum, schema='public'):
        if db_enum == EnumDB.QuintoAndar_ebdb:
            dir = '{}/ebdb'.format(SOURCE_QUERIES_DIR)
        elif db_enum == EnumDB.BI_ODS:
            dir = ODS_QUERIES_DIR
        elif db_enum == EnumDB.BI_DW:
            dir = '{}/{}'.format(DW_QUERIES_DIR, schema)
        else:
            dir = ''

        return '{}/{}.sql'.format(dir, filename)

    @logger
    def get_agent_data(self, table_name, db_enum, dt=None, dtmax=None, schema='public'):
        filename = self._format_query_filename(table_name, db_enum, schema=schema)
        with open(filename) as f:
            raw_query = f.read()

        if dtmax is not None:
            raw_query = raw_query.format(str(dt), str(dtmax))
        elif dt is not None:
            raw_query = raw_query.format(str(dt))

        agent_data = BaseETL.from_db_query(
            db_enum=db_enum,
            query=raw_query
        )

        return agent_data

    @logger
    def truncate_table(self, schema, table, enumdb):
        raw_query = "TRUNCATE TABLE {}.{}"
        query = raw_query.format(schema, table)

        BaseETL.execute_command(
            db_enum=enumdb,
            encoding='UTF8',
            command=query,
            commit=True
        )

    @logger(exclude='data')
    def move_data_to_destination(self, data, table_name, enumdb=EnumDB.BI_ODS, bucket='raw', append=True,
                                 schema='public', decode=True):
        logger.info("m=move_data_to_destination, msg=to destination: {}".format(datetime.now()))

        table = BaseETL.decode_table(data, 'LATIN-1') if decode else data
        BaseETL.bulk_insert(
            table=table,
            table_name='{}.{}'.format(schema, table_name),
            db_enum=enumdb,
            encoding='UTF8',
            append=append,
            commit=True,
            bucket_name='{}/{}/ods/{}'.format(self.bucket_datalake, bucket, table_name))

    @logger(exclude='new_data')
    def split_new_rows(self, new_data, dt):
        infinity_date = '2099-12-31 00:00:00'
        new_table = BaseETL.decode_table(new_data, 'LATIN-1')  # decode table from LATIN-1
        new_table = petl.sort(new_table, key=['dt'])

        # Inserted
        table_ins = petl.select(new_table, lambda rec: str(rec.REVTYPE) == '0')

        table_ins = petl.addfield(table_ins, 'dt_end', infinity_date)
        table_ins = petl.rename(table_ins,
                                {'dt': 'dt_start', 'DadosAgente_id': 'dadosagente_id', 'REVTYPE': 'revtype'})
        table_ins = petl.addfield(table_ins, 'dt', str(dt))
        table_ins = petl.movefield(table_ins, 'dt_end', 3)

        # Updated
        table_upd = petl.select(new_table, lambda rec: str(rec.REVTYPE) == '2')
        table_upd = petl.rename(table_upd,
                                {'dt': 'dt_end', 'DadosAgente_id': 'dadosagente_id', 'REVTYPE': 'revtype'})

        return table_ins, table_upd

    @logger(exclude='data')
    def update_data(self, data, db, table, enumdb, date):
        infinity_date = '2099-12-31 00:00:00'
        upd_data = data
        for row in upd_data:
            if str(row[3]) == '2':
                query = "UPDATE {}.{} SET dt_end='{}', dt='{}' WHERE dadosagente_id={} AND regiao_id={} AND dt_start<'{}' AND dt_end='{}'".format(
                    db, table, row[2], date, row[0], row[1], row[2], infinity_date)
                BaseETL.execute_command(
                    command=query,
                    commit=True,
                    db_enum=enumdb
                )

    @logger
    def create_table_dw(self, table_name, append, dt=None, enumdb=EnumDB.BI_DW, bucket='clean', schema='public'):
        logger.info('m=create_table_dw, table_name = {}, msg=start query to create table'.format(table_name))
        table = self.get_agent_data(table_name=table_name, db_enum=enumdb, dt=dt)

        logger.info('m=create_table_dw, msg=to DW')
        self.move_data_to_destination(data=table, table_name=table_name, enumdb=enumdb, bucket=bucket, append=append,
                                      schema=schema)

    @logger
    def clean_daily_data_in_table(self, enum, schema, dim_name, date_column, dt, format):
        logger.info('m=clean_daily_data_in_table, dim_name={}, msg=start query to clean.'.format(dim_name))

        if format == 'YYYY-MM-DD':
            date_column = 'date({})'.format(date_column)

        query = "DELETE FROM {}.{} WHERE cast({} as varchar) = to_char('{}'::DATE,'{}')".format(schema, dim_name,
                                                                                                date_column,
                                                                                                str(dt), format)

        BaseETL.execute_command(
            db_enum=enum,
            encoding='UTF8',
            command=query,
            commit=True
        )

    @logger
    def clean_greater_than_daily_data_in_table(self, enum, schema, dim_name, date_column, dt):
        logger.info('m=clean_greater_than_daily_data_in_table, dim_name={}, msg=start query to clean.'.format(dim_name))

        query = '''DELETE
                    FROM {0}.{1}
                    WHERE cast({2} as integer) BETWEEN
                    cast(to_char('{3}'::DATE,'YYYYMMDD') as integer) and
                    cast(to_char('{3}'::DATE + interval '21 days','YYYYMMDD') as integer)'''.format(schema, dim_name,
                                                                                                    date_column,
                                                                                                    str(dt))

        BaseETL.execute_command(
            db_enum=enum,
            encoding='UTF8',
            command=query,
            commit=True
        )

    @logger
    def reprocess_old_records(self, exec_dt):
        infinity_date = '2099-12-31 00:00:00'

        query = "UPDATE {}.{} SET {} = date('{}') WHERE date({}) = date('{}')".format('public', 'agent_region_hist',
                                                                                      'dt_end', str(infinity_date),
                                                                                      'dt_end',
                                                                                      str(exec_dt))

        BaseETL.execute_command(
            db_enum=EnumDB.BI_ODS,
            encoding='UTF8',
            command=query,
            commit=True
        )

    @logger
    def insert_dummy(self, table_name, key_column, value='-1', previous_check=False, schema='public'):
        if previous_check:
            if not self.check_dummy_exists(enumdb=EnumDB.BI_DW, schema=schema, table_name=table_name,
                                           key_column=key_column):
                BaseETL.execute_command(
                    'insert into {}.{}({}) values ({});'.format(schema, table_name, key_column, value),
                    db_enum=EnumDB.BI_DW,
                    commit=True
                )
        else:
            BaseETL.execute_command(
                'insert into {}.{}({}) values ({});'.format(schema, table_name, key_column, value),
                db_enum=EnumDB.BI_DW,
                commit=True
            )

    @logger
    def check_dummy_exists(self, enumdb, schema, table_name, key_column):
        table = BaseETL.from_db_query(
            db_enum=enumdb,
            query='SELECT count(1) FROM {}.{} WHERE {} = -1;'.format(schema, table_name, key_column)
        )

        if table[1][0] > 0:
            dummy_exists = True
        else:
            dummy_exists = False

        return dummy_exists

    @logger(exclude=['google_s_a_credentials', 'google_api_scope', 'google_sheets_files'])
    def _get_google_sheets_data(self, google_s_a_credentials, google_api_scope, google_sheets_files, filename):
        gsheets = GoogleSheetsClient(google_s_a_credentials, google_api_scope)

        for item in google_sheets_files['files']:
            if item['fileName'] == filename:
                df_gsheets = gsheets.get_dataframe_from_sheet(sheet_name=item['sheetName'], sheet_id=item['sheetId'])
                snake_case_columns = self._to_snake_case_columns(df_gsheets.columns)
                df_gsheets.rename(columns=snake_case_columns, inplace=True)
                return df_gsheets

        raise ValueError(
            'm=_get_google_sheets_data, filename={}, msg=no filename found in json google sheets schema.'.format(
                filename))

    @logger(exclude=['google_s_a_credentials', 'google_api_scope', 'google_sheets_files'])
    def move_sheets_data_to_datalake(self, google_s_a_credentials, google_api_scope, google_sheets_files, filename,
                                     path):
        df = self._get_google_sheets_data(google_s_a_credentials=google_s_a_credentials,
                                          google_api_scope=google_api_scope, google_sheets_files=google_sheets_files,
                                          filename=filename)
        s3 = S3ToODS(s3_bucket=self.bucket_datalake)
        s3.move_df_to_datalake(df=df, tablename=path)

    @logger(exclude='old_columns')
    def _to_snake_case_columns(self, old_columns):
        _underscorer1 = re.compile(r'(\S)([A-Z][a-z]+)')
        _underscorer2 = re.compile('([a-z0-9])([A-Z])')

        new_columns = {}

        for old_column in old_columns:
            subbed = _underscorer1.sub(r'\1_\2', old_column)
            new_column = _underscorer2.sub(r'\1_\2', subbed).lower()
            new_column = new_column.replace(' ', '_')
            new_columns.update({old_column: new_column})

        return new_columns

    @logger
    def get_datalake_data_from_filequery(self, file_name):
        data_acc_aws_access_key_id = os.environ.get('DATA_AWS_ACCESS_KEY_ID')
        data_acc_aws_secret_access_key = os.environ.get('DATA_AWS_SECRET_ACCESS_KEY')
        a = AthenaClient(self.bucket_datalake, data_acc_aws_access_key_id, data_acc_aws_secret_access_key)
        df = a.execute_file_query_and_return_dataframe(
            filename='{}/agent/{}.sql'.format(DATALAKE_QUERIES_DIR, file_name))
        return petl.fromdataframe(df)
