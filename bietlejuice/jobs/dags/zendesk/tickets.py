from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk

logger = QuintoAndarLogger('ZendeskTickets')


class ZendeskTickets(Zendesk):
    TABLE = 'tickets'

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskTickets, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, bucket_type, class_):
        self._upsert_single_partition(bucket_type=bucket_type, class_=self.TABLE)
