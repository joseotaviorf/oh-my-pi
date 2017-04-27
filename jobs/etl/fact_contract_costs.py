from datetime import datetime

from jobs.base.base_etl import BaseETL, EnumDb

print("Start query: {}".format(datetime.now()))

BaseETL.execute_command(
    db_enum=EnumDb.BI_DW,
    command="""truncate table fact_contract_costs""",
    commit=True
)

BaseETL.move_table(table_name='vw_contract_costs',
                   enum_db_source=EnumDb.BI_ODS,
                   enum_db_dest=EnumDb.BI_DW,
                   table_name_dest='fact_contract_costs')

print("End query: {}".format(datetime.now()))
