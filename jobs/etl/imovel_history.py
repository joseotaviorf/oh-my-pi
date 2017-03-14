from jobs.base.base_etl import BaseETL, EnumDb
from datetime import datetime, timedelta
import petl


max_date = BaseETL.from_db_query(
    db_enum=EnumDb.BI_ODS,
    query="select max(date_status_changed) from imovel_status_history"
)

max_date = max_date[1][0]  # datetime.today()-timedelta(days=1)

query_extract = """
        select
            *,
            now()
        from
          v_ImovelStatusHistory
        where
          id in
        (
            select
              distinct id
            from
              v_Imovel_AUD  a
            WHERE
              id in (892774974, 892796245) and
              a.date_status_changed >= '{}'
              and a.date_status_changed < '{}'
        )
        ;
    """.format(
    max_date if max_date else '2012-01-01', # -timedelta(days=1) ??
    datetime.today().date()
)

imoveis = BaseETL.from_db_query(
    db_enum=EnumDb.QuintoAndar_ebdb,
    query=query_extract
)
imoveis = BaseETL.decode_table(imoveis, 'latin-1')

q_del = \
"""
    delete from
        imovel_status_history
    where
        id in {}
""".format(
    list(petl.aggregate(imoveis, 'id')['id'])
).replace(
    '[','('
).replace(
    ']',')'
)

BaseETL.bulk_insert(
    table=imoveis,
    table_name='stg.imovel_status_history',
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True
)

conn = BaseETL.get_connection(db_enum=EnumDb.BI_ODS, encoding='UTF-8')

BaseETL.execute_command(command=q_del, conn=conn, commit=False)

BaseETL.execute_command(
    command="""
    insert into public.imovel_status_history
    select * from stg.imovel_status_history
    """,
    conn=conn,
    commit=False
)

conn.commit()
conn.close()
