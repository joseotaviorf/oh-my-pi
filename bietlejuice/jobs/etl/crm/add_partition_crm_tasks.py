import logging
import sys
from datetime import datetime

from qa_python_utils.aws.athena import AthenaClient

logging.basicConfig(level=logging.INFO)
_logger = logging.getLogger(__name__)

athena = AthenaClient('5a-datalake')

if len(sys.argv) < 4:
    raise Exception('Missing Parameters')

logging.info("START - ADD PARTITION: {}".format(datetime.utcnow()))

database = sys.argv[1]
table_name = sys.argv[2]
date = sys.argv[3]
if len(date) >= 10:
    date = date[:10]
partition = "extracted_on='{}'".format(date)

athena.add_partition(database, table_name, partition)

logging.info("END - ADD PARTITION: {}".format(datetime.utcnow()))
