import logging
from datetime import datetime
from qa_python_utils.aws.athena import AthenaClient
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
import sys

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

athena = AthenaClient('5a-datalake')
table_name = 'zendesk.chats'
file_name = './db/2.datalake/queries/zendesk/chats.sql'

if len(sys.argv) < 3:
    raise Exception('Missing Parameters')

logging.info("Reading from S3: {}".format(datetime.utcnow()))
date = sys.argv[2]
if len(date) >= 10:
    date = date[:10]
data_frame = athena.execute_file_query_and_return_dataframe(file_name, '{}'.format(date))

logging.info("To Staging: {}".format(datetime.utcnow()))
BaseETL.dataframe_to_db(
    enum_db=EnumDb.BI_DW,
    df=data_frame,
    table_name=table_name,
    encoding='utf-8',
    append=True
)

