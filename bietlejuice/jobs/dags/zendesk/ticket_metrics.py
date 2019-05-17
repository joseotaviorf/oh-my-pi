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
        self._upsert_single_partition(bucket_type=bucket_type, class_=ZendeskTicketMetrics.CLASS_ENUM)

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_ticket_metrics', str),
            ('url_ticket_metrics', str),
            ('minutes_first_calendar_resolution', str),
            ('minutes_first_business_resolution', str),
            ('ts_requester_updated', str),
            ('ts_solved', str),
            ('assignee_stations', str),
            ('ts_latest_comment_added', str),
            ('reopens', str),
            ('minutes_full_calendar_resolution', str),
            ('minutes_full_business_resolution', str),
            ('id_ticket', str),
            ('replies', str),
            ('minutes_calendar_requester_wait', str),
            ('minutes_business_requester_wait', str),
            ('minutes_calendar_agent_wait', str),
            ('minutes_business_agent_wait', str),
            ('minutes_calendar_on_hold', str),
            ('minutes_business_on_hold', str),
            ('group_stations', str),
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
