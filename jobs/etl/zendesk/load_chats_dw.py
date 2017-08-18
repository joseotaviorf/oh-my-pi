import logging
from datetime import datetime
from qa_python_utils.aws.athena import AthenaClient
from jobs.base.base_etl import BaseETL
from jobs.base.enum_db import EnumDb
import pandas as pd

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

athena = AthenaClient('5a-datalake')
table_name = 'zendesk.chats'

file_name = '/home/felipe/Projects/bi-etl-ejuice/db/2.datalake/queries/zendesk_chats.sql'

print("Reading from S3: {}".format(datetime.utcnow()))
data_frame = athena.execute_file_query_and_return_dataframe(file_name, "'2017-08-14'")

# data_frame = pd.read_csv('/home/felipe/Downloads/a346dcd3-82f1-4c49-8e3a-a8ecf763ae6d.csv', keep_default_na=False)

print("To Staging: {}".format(datetime.utcnow()))
data_frame.drop('times', axis=1, inplace=True)

BaseETL.dataframe_to_db(
    enum_db=EnumDb.BI_DW,
    df=data_frame,
    table_name=table_name,
    encoding='utf-8'
)