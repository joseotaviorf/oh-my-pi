from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
import sys
import os
from datetime import datetime


args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename().replace('dim_','')

table = BaseETL.from_db_query(
    db_enum=EnumDb.QuintoAndar_ebdb,
    query="""
    select
      id,
      dataConsolidado ,
      dataDespesa ,
      pagante ,
      responsavel ,
      tipo ,
      valor,
      cobranca_id ,
      descricao ,
      automatica+0 as automatica,
      atualizadoEm ,
      criadoEm 
    from
      Despesa
  """)

print("To ODS: {}".format(datetime.now()))

table = BaseETL.decode_table(table, 'LATIN-1')

BaseETL.bulk_insert(
    table=table,
    table_name=process_name,
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True,
    bucket_name='{}/raw/ods/{}'.format(bucket_datalake, process_name)
)

BaseETL.copy_file_between_s3_buckets(
    bucket_source=bucket_datalake,
    bucket_destination=bucket_datalake,
    full_filename_source='raw/ods/{0}/{0}.csv'.format(process_name),
    full_filename_dest='clean/ods/{0}/{0}.csv'.format(process_name)
)