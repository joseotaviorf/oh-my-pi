from jobs.base.base_etl import BaseETL, EnumDb
import os
from datetime import datetime

bucket_datalake = os.environ['bi-datalake-s3-bucket']
table_name = BaseETL.get_current_filename()
process_name = table_name.replace('fact_','')

print("Start query: {}".format(datetime.now()))

BaseETL.move_table_to_dw(
    table_name='vw_contract_costs',
    enum_db_source=EnumDb.BI_ODS,
    enum_db_dest=EnumDb.BI_DW,
    table_name_dest=table_name,
    append=False,
    bucket_name='{}/clean/ebdb/{}'.format(bucket_datalake, process_name),
    process_name=process_name
)

print("End query: {}".format(datetime.now()))
