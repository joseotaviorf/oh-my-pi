from jobs.base.base_etl import BaseETL, EnumDb, petl
from datetime import datetime


print("Start query: {}".format(datetime.now()))

table = BaseETL.from_db_table(
db_enum=EnumDb.QuintoAndar_ebdb,
table_name='DadosAgente_Regiao')

print("To ODS: {}".format(datetime.now()))

table = BaseETL.decode_table(table, 'LATIN-1')

BaseETL.bulk_insert(
    table=table,
    table_name='agent_region',
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True
)