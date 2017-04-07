from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
import sys

args = sys.argv

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



BaseETL.to_db(
    db_enum=EnumDb.BI_ODS,
    data_table=t,
    table_name='charging',
    append=False,
    create=False
)