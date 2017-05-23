from jobs.base.base_etl import BaseETL, EnumDb
from datetime import datetime
import petl
import os

table_name='imovel_status_history'

# get max loaded date
max_date = BaseETL.from_db_query(
    db_enum=EnumDb.BI_ODS,
    query="select max(date_status_changed) from {}".format(table_name)
)
max_date = max_date[1][0]

# create the extraction
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
              -- id in (892774974, 892796245) and
              a.date_status_changed >= '{}'
              and a.date_status_changed < '{}'
        )
        ;
    """.format(
    max_date if max_date else '2012-01-01',
    datetime.today().date()
)
imoveis = BaseETL.from_db_query(
    db_enum=EnumDb.QuintoAndar_ebdb,
    query=query_extract
)
imoveis = BaseETL.decode_table(imoveis, 'latin-1')

BaseETL.bulk_insert(
    table=imoveis,
    table_name='stg.{}'.format(table_name),
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True
)

### LOAD ####
#create connection
conn = BaseETL.get_connection(db_enum=EnumDb.BI_ODS, encoding='UTF-8')

# delete repeated ids
q_del = 'delete from {} where id in {}'.format(
    table_name,
    list(petl.aggregate(imoveis, 'id')['id'])
).replace(
    '[','('
).replace(
    ']',')'
)
BaseETL.execute_command(command=q_del, conn=conn, commit=False)


# load into ods/datalake (in same transaction)
BaseETL.execute_command(
    command='insert into public.{0} select * from stg.{0}'.format(table_name),
    conn=conn,
    commit=False
)

# commit
conn.commit()
conn.close()

# move to lake
BaseETL.dump_ODS_to_datalake(table_name)
