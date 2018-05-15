import os
import sys

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb

args = sys.argv
bucket_datalake = os.environ['bi-datalake-s3-bucket']
process_name = BaseETL.get_current_filename().replace('dim_', '')

t = BaseETL.from_db_query(
    db_enum=EnumDb.QuintoAndar_ebdb,
    query="""
    select
      id
      ,dataInquilinoPagou
      ,dataPagarProprietario
      ,dataProprietarioFoiPago
      ,fimPeriodo
      ,inicioPeriodo
      ,inquilinoPagou+0 as inquilinoPagou
      ,proprietarioFoiPago+0 as proprietarioFoiPago
      ,status
      ,vencimentoBoleto
      ,contrato_id
      ,valorTotalInquilino
      ,valorTotalProprietario
      ,dataFechamento
      ,boletoClone
      ,criadoEm
      ,valorRecebido
      ,gerarNF
      ,atualizadoEm
      ,regerarDespesas
      ,dataAutoEnvioDemonstrativoProp
      ,linhaDigitavel
      ,dataEnvioSmsLembrete
    from
      Cobranca
    """)

BaseETL.bulk_insert(
    table=t,
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
