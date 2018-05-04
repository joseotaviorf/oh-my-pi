import logging
from datetime import datetime

from qa_python_utils.aws.athena import AthenaClient

from bietlejuice.jobs.base.base_etl import BaseETL
from bietlejuice.jobs.base.enum_db import EnumDb

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

athena = AthenaClient('5a-datalake')
file_name = './bietlejuice/db/2.datalake/queries/affiliate_payments.sql'
process_name = BaseETL.get_current_filename()

logging.info("Reading from S3: {}".format(datetime.utcnow()))

data_frame = athena.execute_file_query_and_return_dataframe(file_name)

logging.info("START - To Staging: {}".format(datetime.utcnow()))

BaseETL.dataframe_to_db(
    enum_db=EnumDb.BI_ODS,
    df=data_frame,
    table_name=process_name,
    encoding='utf-8',
    append=False
)

logging.info("END - To Staging: {}".format(datetime.utcnow()))
