import os
from datetime import datetime

from bietlejuice.jobs.base.base_etl import BaseETL, EnumDb

bucket_datalake = os.environ['bi-datalake-s3-bucket']
table_name = BaseETL.get_current_filename()
process_name = table_name.replace('fact_', '')

print("Start query (vw_base_ticket_task): {}".format(datetime.now()))

table = BaseETL.from_db_query(
    db_enum=EnumDb.BI_ODS,
    query='select * from unit_economics.vw_base_ticket_task;'
)

table = BaseETL.decode_table(table, 'LATIN-1')
BaseETL.bulk_insert(
    table=table,
    table_name='unit_economics.tbl_base_ticket_task',
    db_enum=EnumDb.BI_ODS,
    encoding='UTF8',
    append=False,
    commit=True,
    bucket_name='{}/raw/ods/base_ticket_task'.format(bucket_datalake)
)

print("End query (vw_base_ticket_task): {}".format(datetime.now()))
print("Start query (fact): {}".format(datetime.now()))

BaseETL.move_table_to_dw(
    table_name='unit_economics.vw_fact_property_economics',
    enum_db_source=EnumDb.BI_ODS,
    enum_db_dest=EnumDb.BI_DW,
    table_name_dest=table_name,
    append=False,
    bucket_name='{}/clean/ods/{}'.format(bucket_datalake, process_name),
    process_name=process_name
)

print("End query (fact): {}".format(datetime.now()))
