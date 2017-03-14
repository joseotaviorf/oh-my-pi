from jobs.base.base_etl import BaseETL, EnumDb

conn = BaseETL.get_connection(db_enum=EnumDb.BI_DW, encoding='UTF8')
BaseETL.execute_command(
    conn=conn,
    command="""truncate table fact_listing_status""",
    commit=True
)

BaseETL.move_table(
    table_name = 'vw_fact_listing_status',
    enum_db_source = EnumDb.BI_ODS,
    enum_db_dest = EnumDb.BI_DW,
    table_name_dest='fact_listing_status',
    append=False,
    encoding='utf8'
)

