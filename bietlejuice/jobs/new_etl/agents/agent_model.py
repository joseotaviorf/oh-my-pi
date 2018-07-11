from datetime import datetime

import petl
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from bietlejuice.jobs.new_etl import EBDB_QUERIES_DIR, DW_QUERIES_DIR
from bietlejuice.jobs.new_etl.agents import ODS_QUERIES_DIR
from qa_python_utils.default_logger import _logger, logger


class Agent(object):
    def __init__(self, bucket_name):
        self.bucket_datalake = bucket_name

    def __format_query_filename(self, filename, db_enum):
        if db_enum == EnumDb.QuintoAndar_ebdb:
            dir = EBDB_QUERIES_DIR
        elif db_enum == EnumDb.BI_ODS:
            dir = ODS_QUERIES_DIR
        elif db_enum == EnumDb.BI_DW:
            dir = DW_QUERIES_DIR
        else:
            dir = ''

        return '{}/{}.sql'.format(dir, filename)

    @logger
    def get_agent_data(self, f_name, db_enum, dt=None, dtmax=None):
        filename = self.__format_query_filename(f_name, db_enum)
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
    def move_data_to_destination(self, data, table_name, enumdb=EnumDb.BI_ODS, bucket='raw', append=True):
        _logger.info("m=move_data_to_destination, To Destination: {}".format(datetime.now()))

        table = BaseETL.decode_table(data, 'LATIN-1')
        BaseETL.bulk_insert(
            table=table,
            table_name=table_name,
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
    def create_dim_or_fact_dw(self, dim_name, append, dt=None, enumdb=EnumDb.BI_DW, bucket='clean'):
        _logger.info('m=create_dim_or_fact_dw, Start query to create {}: {}'.format(dim_name, datetime.now()))
        table = self.get_agent_data(f_name=dim_name, db_enum=enumdb, dt=dt)

        _logger.info('m=create_dim_or_fact_dw, To DW: {}'.format(datetime.now()))
        self.move_data_to_destination(data=table, table_name=dim_name, enumdb=enumdb, bucket=bucket, append=append)

    @logger
    def clean_daily_data_in_table(self, enum, schema, dim_name, date_column, dt, format):
        _logger.info('m=clean_daily_data_in_table, Start query to clean {}: {}'.format(dim_name, str(dt)))

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
    def reprocess_old_records(self, exec_dt):
        infinity_date = '2099-12-31 00:00:00'

        query = "UPDATE {}.{} SET {} = date('{}') WHERE date({}) = date('{}')".format('public', 'agent_region_hist',
                                                                                      'dt_end', str(infinity_date),
                                                                                      'dt_end',
                                                                                      str(exec_dt))

        BaseETL.execute_command(
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            command=query,
            commit=True
        )

    @logger
    def insert_dummy(self, table_name, key_column, value='-1', previous_check=False):
        if previous_check:
            if not self.check_dummy_exists(enumdb=EnumDb.BI_DW, schema='public', table_name=table_name,
                                           key_column=key_column):
                BaseETL.execute_command(
                    'insert into {}({}) values ({});'.format(table_name, key_column, value),
                    db_enum=EnumDb.BI_DW,
                    commit=True
                )
        else:
            BaseETL.execute_command(
                'insert into {}({}) values ({});'.format(table_name, key_column, value),
                db_enum=EnumDb.BI_DW,
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
