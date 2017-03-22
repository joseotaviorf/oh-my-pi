from jobs.base.base_etl import BaseETL, EnumDb
import sys

count_ids = BaseETL.from_db_query(
    db_enum=EnumDb.BI_ODS,
    query="select count(distinct id) from imovel_status_history")[1][0]

offset = 0
offset_inc = 1000

# conn = BaseETL.get_connection()
BaseETL.execute_command(
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8', #conn=conn,
    command="""truncate table imovel_status_full_history""",
    commit=True
)

while offset <= count_ids:
    print('BEGINING OFFSET: {}'.format(offset))
    BaseETL.execute_command(
        db_enum=EnumDb.BI_ODS,
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
    sys.stdout.flush()
    offset += offset_inc

print ('END')
sys.stdout.flush()

#conn.close()
