from jobs.base.base_etl import BaseETL, EnumDb

ids = BaseETL.from_db_query(
    db_enum=EnumDb.QuintoAndar_ebdb,
    query="select distinct id from Imovel_AUD order by 1 desc")[1:]

imoveis = []
conn = BaseETL.get_connection(db_enum=EnumDb.QuintoAndar_ebdb)
for items in ids:
    id = items[0]
    imovel = BaseETL.from_db_query(
        db_enum=EnumDb.QuintoAndar_ebdb,
        query="select * from v_ImovelStatusHistory where id  = {};".format(id),
        conn=conn
    )
    imovel = BaseETL.decode_table(imovel, 'latin-1')
    if len(imoveis) == 0:
        imoveis.extend(map(list, imovel)) # insere com header se for a primeira vez
    elif len(imovel) > 2:
        imoveis.extend(map(list, imovel[1:]))
    else:
        imoveis.append(list(imovel[1]))

conn.close()

# BaseETL.to_db(
#     db_enum=EnumDb.BI_ODS,
#     data_table=imoveis,
#     table_name='imovel_status_history',
#     encoding='UTF8',
#     append=False,
#     create=False,
#     commit=True
# )


BaseETL.bulk_insert(
    table=imoveis,
    table_name='imovel_status_history',
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True
)