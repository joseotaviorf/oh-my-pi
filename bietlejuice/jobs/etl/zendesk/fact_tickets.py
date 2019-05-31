from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskFactTickets')


class ZendeskFactTickets(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.FACT_TICKETS
    SK_COLUMN = 'sk_ticket'

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskFactTickets, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def move_to_staging(self, **kwargs):
        return self._move_to_staging(self.CLASS_ENUM, self.SK_COLUMN)

    @logger
    def move_to_prod(self, **kwargs):
        return self._move_to_prod(self.CLASS_ENUM, self.SK_COLUMN)
