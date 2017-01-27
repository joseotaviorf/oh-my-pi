from jobs.base.base_etl import BaseETL, EnumDb

ids = BaseETL.from_db_query(
    db_enum=EnumDb.BI_ODS,
    query="select distinct id from imovel_status_history order by 1 desc")[1:]

imoveis = []
count_ids = 0
erros = []
append = False
conn = BaseETL.get_connection(db_enum=EnumDb.BI_ODS, encoding='UTF8')
while ids:
    id = ids[0]
    count_ids += 1
    imovel = BaseETL.from_db_query(
        db_enum=EnumDb.QuintoAndar_ebdb,
        query="select * from f_list_imovel_status_full_history ({}) where final_status_date_position;".format(id[0]),
        conn=conn
    )
    # imovel = BaseETL.decode_table(imovel, 'utf-8')
    if len(imoveis) == 0:
        imoveis.extend(map(list, imovel)) # insere com header se for a primeira vez
    elif len(imovel) > 2:
        imoveis.extend(map(list, imovel[1:])) # insere multiplas linhas
    elif len(imovel) > 1:
        imoveis.append(list(imovel[1])) # insere somente uma
    else:
        print ('Imovel nao encontrado: {}'.format(id))
        erros.append(id)

    ids.remove(id)
    if count_ids == 2000 or len(ids) == 0:
        BaseETL.bulk_insert(
            table=imoveis,
            table_name='imovel_status_full_history',
            db_enum=EnumDb.BI_ODS,
            encoding='UTF8',
            append=append,
            commit=True
        )
        count_ids = 0
        imoveis = []
        append = True

conn.close()


if erros:
    print ('Imoveis com erro: {}'. format(erros))