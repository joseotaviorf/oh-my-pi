import logging
from datetime import datetime

from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDB

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

athena = AthenaClient('5a-amplitude-events')
process_name = BaseETL.get_current_filename()

print("Updating partitions: {}".format(datetime.now()))

database = 'amplitude'
table_list = [
    'ev_ios_booking_media_sources',
    'ev_web_booking_media_sources',
    'ev_android_booking_media_sources'
]
for t in table_list:
    athena.msck_repair_table(database, t)

file_name = './bietlejuice/db/2.datalake/queries/extract_booking_media_sources.sql'

print("Reading from S3: {}".format(datetime.now()))

data_frame = athena.execute_file_query_and_return_dataframe(file_name)

print("To ODS: {}".format(datetime.now()))

BaseETL.execute_command(
    command="""truncate {};""".format(process_name),
    db_enum=EnumDB.BI_ODS,
    encoding='utf-8',
    commit=True
)

BaseETL.dataframe_to_ods(
    df=data_frame,
    table_name=process_name,
    encoding='utf-8'
)
