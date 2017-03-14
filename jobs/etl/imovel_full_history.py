from jobs.base.base_etl import BaseETL, EnumDb

count_ids = BaseETL.from_db_query(
    db_enum=EnumDb.BI_ODS,
    query="select count(distinct id) from imovel_status_history")[1][0]

offset = 0
offset_inc = 1000

conn = BaseETL.get_connection(db_enum=EnumDb.BI_ODS, encoding='UTF8')
BaseETL.execute_command(
    conn=conn,
    command="""truncate table imovel_status_full_history""",
    commit=True
)

while offset <= count_ids:
    print('BEGINING OFFSET: {}'.format(offset))
    BaseETL.execute_command(
        conn=conn,
        command=
        """
            insert into
                imovel_status_full_history
            select *
            from
                f_list_imovel_status_full_history({},{})
            where
                all_status_date_position_flag;
        """.format(offset, offset_inc),
        encoding='UTF8',
        commit=True
    )
    print('OFFSET: {} SUCCESSEFULLY INSERTED'.format(offset))
    offset += offset_inc

conn.close()
