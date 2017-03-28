from jobs.base.base_etl import BaseETL, EnumDb

BaseETL.execute_command(
    db_enum=EnumDb.BI_DW,
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

