import os
import sys
from io import BytesIO

import boto3
import pandas as pd
import petl
from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb
from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger, _logger

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
schema_name = 'ebdb'

CLEAN_TABLE_INFOS = [
    {'original_name': 'ContratoPessoa', 'new_name': 'contract_person'},
    {'original_name': 'PropostaProponente', 'new_name': 'proponent_proposal'},
    {'original_name': 'Usuario', 'new_name': 'user'},
    {'original_name': 'Entrance', 'new_name': 'entrance'},
    {'original_name': 'Agendamento', 'new_name': 'booking'},
    {'original_name': 'Visita', 'new_name': 'visit'},
    {'original_name': 'Visitor', 'new_name': 'visitor'},
    {'original_name': 'FollowUpDetails', 'new_name': 'follow_up_details'},
    {'original_name': 'UsuarioRevisionEntity', 'new_name': 'usuario_revision_entity'},
    {'original_name': 'OperacaoContaCorrente', 'new_name': 'operacao_conta_corrente'},
    {'original_name': 'ContaCorrente', 'new_name': 'conta_corrente'},
    {'original_name': 'Imovel_informacoesVisita_AUD', 'new_name': 'informacoes_visita_aud'},
    {'original_name': 'Imovel', 'new_name': 'property'},
    {'original_name': 'DadosFotografo', 'new_name': 'photographer_data'},
    {'original_name': 'DadosAfiliado', 'new_name': 'affiliate_data'},
    {'original_name': 'DadosVendedor', 'new_name': 'seller_data'},
    {'original_name': 'DadosAgente_tipos', 'new_name': 'agent_data_type'},
    {'original_name': 'Contrato', 'new_name': 'contract'},
    {'original_name': 'Offer', 'new_name': 'offer'},
]


class EBDBDatalake(object):
    def __init__(self):
        self.s3_client = boto3.resource('s3')
        self.athena_client = AthenaClient(bucket_datalake)

    @logger
    def move_to_datalake(self, table_name):
        now = BaseETL.now()
        db = EnumDb.QuintoAndar_ebdb

        _logger.info('m=move_to_datalake, msg=start query: {}'.format(now))

        schema = BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, table_name, schema_name, False)
        schema = petl.todataframe(schema)

        columns = []
        for _, row in schema.iterrows():
            if row.DATA_TYPE == 'bit':
                columns.append("""cast(`{column}` as unsigned) as `{column}`""".format(column=row.COLUMN_NAME))
            elif row.DATA_TYPE == 'longblob':
                columns.append("""AsText(`{column}`) as `{column}`""".format(column=row.COLUMN_NAME))
            else:
                columns.append("""`{}`""".format(row.COLUMN_NAME))

        # get data from table
        table = BaseETL.from_db_query(db, """select {} from {}""".format(', '.join(columns), table_name))

        _logger.info('m=move_to_datalake, msg=to ODS: {}'.format(now))

        table = BaseETL.decode_table(table, 'LATIN-1')  # decode table from LATIN-1
        table = petl.convertall(table, unicode)  # convert all fields to unicode

        # save table into datalake
        file_path = 'raw/{1}/{2}/{2}.csv'.format(bucket_datalake, schema_name, table_name)
        df_table = petl.todataframe(table)

        # replace Nan for SQL Null
        df_table.replace(['None'], [None], inplace=True)
        df_table = df_table.astype(object).where(pd.notnull(df_table), None)

        # replace '\n' and '\r for space
        df_table.replace('\n', ' ', regex=True, inplace=True)
        df_table.replace('\r', ' ', regex=True, inplace=True)

        csv_buffer = BytesIO()
        df_table.to_csv(csv_buffer, index=False, sep=',', encoding='utf-8', header=False)

        self.s3_client.Object(bucket_datalake, file_path).put(Body=csv_buffer.getvalue())

        _logger.info('m=move_to_datalake, msg={} moved to Datalake!'.format(table_name))

    def transform_tables_to_clean(self, table_infos, ddl_suffix):
        _logger.info('m=transform_tables_to_clean, msg=init')

        for table_info in table_infos:
            df = self.athena_client.execute_query_and_return_dataframe("""
                  select * from datalake_raw.ebdb_{}""".format(table_info['original_name'])
                                                                       )

            self.athena_client.create_parquet_from_df(
                key='clean/ebdb/{0}/{0}.parq'.format(table_info['new_name']),
                df=df
            )

            self.create_external_table(table_info['new_name'], ddl_suffix, table_info['original_name'],
                                       'datalake_clean')

    @logger
    def get_type_conversion_dict(self):
        conversions_table = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query="""
                select 
                    distinct	DATA_TYPE,
                    case  
                        when DATA_TYPE in ('bigint', 'smallint', 'double', 'timestamp', 'int') then DATA_TYPE
                        when DATA_TYPE in ('datetime', 'time') then 'timestamp'
                        when DATA_TYPE in ('bit', 'tinyint') then 'smallint'
                        when DATA_TYPE in ('float', 'decimal', 'numeric') then 'double'
                        else 'string' 
                    end as ret
                from information_schema.COLUMNS
            """
        )
        conversions_table.pop(0)
        conversions = {}
        for k, v in conversions_table:
            conversions[k] = v
        return conversions

    def create_external_table(self, table_name, ddl_suffix, original_table_name=None, athena_db='datalake_raw'):
        if not original_table_name:
            original_table_name = table_name

        columns = BaseETL.get_columns_schema(EnumDb.QuintoAndar_ebdb, original_table_name, schema_name)
        self.athena_client.execute_query_and_wait_for_results(
            'drop table if exists {}.{}_{};'.format(athena_db, schema_name, table_name))

        command = 'create external table {}.{}_{} (\n'.format(athena_db, schema_name, table_name)
        for column, original_type in columns:
            command += '\t{} string,\n'.format(column)
            # command += '\t{} {},\n'.format(column, conv[original_type])
        command = command[:-2]  # remove last comma
        command += ddl_suffix.format(bucket_datalake, schema_name, table_name)

        self.athena_client.execute_query_and_wait_for_results(command)

    @logger
    def get_table_names(self, skip_header=True):
        sql_tables = """
        select TABLE_NAME
        from information_schema.TABLES
        where TABLE_SCHEMA = '{}'
        and TABLE_TYPE = 'BASE TABLE'    
    """.format(schema_name)
        table_names = BaseETL.from_db_query(
            db_enum=EnumDb.QuintoAndar_ebdb,
            query=sql_tables
        )
        if skip_header:
            table_names.pop(0)  # remove header
        return table_names


if __name__ == '__main__':
    ebdb_datalake = EBDBDatalake()
    table_names = ebdb_datalake.get_table_names()

    if args[1] == 'move':
        for table_name in table_names:
            ebdb_datalake.move_to_datalake(table_name[0])
    elif args[1] == 'create_raw_tables':
        conversions = ebdb_datalake.get_type_conversion_dict()
        ddl_suffix = """) row format serde 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
                                 with serdeproperties (
                                   'separatorChar' = ',',
                                   'quoteChar' = '\"'
                                 )
                                stored as textfile
                                location 's3://{}/raw/{}/{}/'"""
        for table_name in table_names:
            ebdb_datalake.create_external_table(table_name[0], ddl_suffix)
    elif args[1] == 'transform_tables_to_clean':
        ddl_suffix = """) stored as parquet
                                location 's3://{}/clean/{}/{}/'"""
        ebdb_datalake.transform_tables_to_clean(CLEAN_TABLE_INFOS, ddl_suffix)
    else:
        _logger.info('m=__main__, msg=arg \'{}\' not recognized'.format(args[1]))
