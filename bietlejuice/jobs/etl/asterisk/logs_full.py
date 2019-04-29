from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.etl.asterisk.asterisk_table_enum import AsteriskTableEnum

logger = QuintoAndarLogger('AsteriskLogsFull')


class AsteriskLogsFull(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.LOGS_FULL

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskLogsFull, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_partition(self, bucket_type, class_):
        self._upsert_partition(bucket_type=bucket_type, class_=AsteriskLogsFull.CLASS_ENUM)
