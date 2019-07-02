from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskTicketMetrics')


class ZendeskTicketMetrics(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.TICKET_METRICS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskTicketMetrics, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, class_, bucket_type):
        self._upsert_single_partition(bucket_type=bucket_type,
                                      class_=ZendeskTicketMetrics.CLASS_ENUM,
                                      integration_name='zendesk_tickets')

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_ticket_metrics', str),
            ('url_ticket_metrics', str),
            ('ts_requester_updated', str),
            ('ts_solved', str),
            ('assignee_stations', str),
            ('ts_latest_comment_added', str),
            ('reopens', str),
            ('id_ticket', str),
            ('replies', str),
            ('group_stations', str),
            ('minutes_reply_calendar', str),
            ('minutes_reply_business', str),
            ('minutes_first_resolution_calendar', str),
            ('minutes_first_resolution_business', str),
            ('minutes_full_resolution_calendar', str),
            ('minutes_full_resolution_business', str),
            ('minutes_requester_wait_calendar', str),
            ('minutes_requester_wait_business', str),
            ('minutes_agent_wait_calendar', str),
            ('minutes_agent_wait_business', str),
            ('minutes_on_hold_calendar', str),
            ('minutes_on_hold_business', str),
            ('ts_initially_assigned', str),
            ('ts_assignee_updated', str),
            ('ts_assigned', str),
            ('ts_created', str),
            ('ts_created_local', str),
            ('ts_updated', str),
            ('ts_load', str)
        ])

        self._move_to_clean_partitioned(
            class_=ZendeskTicketMetrics.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
