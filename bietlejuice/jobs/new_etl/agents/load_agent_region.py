from datetime import datetime

import boto3
import petl
from __init__ import QUERIES_DIR, ODS_QUERIES_DIR
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from qa_python_utils.default_logger import _logger


class Agent_Region(object):
    def __init__(self):
        self.schema_name = ''
        self.bucket_datalake = '5a-datalake'
        self.s3_client = boto3.resource('s3')

    def __format_query_filename(self, filename, db_enum):
        if db_enum == EnumDb.QuintoAndar_ebdb:
            dir = QUERIES_DIR
        elif db_enum == EnumDb.BI_ODS:
            dir = ODS_QUERIES_DIR
        return '{}/{}.sql'.format(dir, filename)

    def get_agent_region(self, f_name, db_enum, dt=None):
        filename = self.__format_query_filename(f_name, db_enum)
        with open(filename) as f:
            raw_query = f.read()

        if dt is not None:
            raw_query = raw_query.format(str(dt))

        agent_region_data = BaseETL.from_db_query(
            db_enum=db_enum,
            query=raw_query
        )

        return agent_region_data

    def clean_agent_region(self, schema, table):
        filename = "TRUNCATE TABLE {}.{}"
        raw_query = filename.format(schema, table)

        BaseETL.execute_command(
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',  # conn=conn,
            command=raw_query,
            commit=True
        )

    def move_data_to_ods(self, data, table_name):
        _logger.info("To ODS: {}".format(datetime.now()))
        table = BaseETL.decode_table(data, 'LATIN-1')
        BaseETL.bulk_insert(
            table=table,
            table_name=table_name,
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=True,
            commit=True,
            bucket_name='{}/raw/ods/{}'.format(self.bucket_datalake, table_name))

    def split_new_rows(self, new_data, dt):
        infinity_date = '2099-12-31 00:00:00'
        new_table = BaseETL.decode_table(new_data, 'LATIN-1')  # decode table from LATIN-1
        new_table = petl.sort(new_table, key=['dt'])
        print('started')
        print(petl.nrows(new_table))

        # Inserted
        table_ins = petl.select(new_table, lambda rec: str(rec.REVTYPE) == '0')
        print(petl.nrows(table_ins))
        print(petl.head(table_ins, 5))
        table_ins = petl.addfield(table_ins, 'dt_end', infinity_date)
        table_ins = petl.rename(table_ins,
                                {'dt': 'dt_start', 'DadosAgente_id': 'dadosagente_id', 'REVTYPE': 'revtype'})
        table_ins = petl.addfield(table_ins, 'dt', str(dt))
        table_ins = petl.movefield(table_ins, 'dt_end', 3)
        print(petl.nrows(table_ins))
        print(petl.head(table_ins, 5))

        # Updated
        table_upd = petl.select(new_table, lambda rec: str(rec.REVTYPE) == '2')
        table_upd = petl.rename(table_upd,
                                {'dt': 'dt_end', 'DadosAgente_id': 'dadosagente_id', 'REVTYPE': 'revtype'})
        print(petl.nrows(table_upd))
        print(petl.head(table_upd, 5))

        return table_ins, table_upd

    def insert_new_data(self, data, table):
        self.move_data_to_ods(data, table)

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
