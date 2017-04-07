from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
import sys

args = sys.argv

t = BaseETL.from_db_query(
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


BaseETL.to_db(
    db_enum=EnumDb.BI_ODS,
    data_table=t,
    table_name='expense',
    append=False,
    create=False
)