from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskTickets')


class ZendeskTickets(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.TICKETS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskTickets, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, class_, bucket_type):
        self._upsert_single_partition(bucket_type=bucket_type,
                                      class_=ZendeskTickets.CLASS_ENUM,
                                      integration_name='zendesk_tickets')

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_ticket', str),
            ('satisfaction_rating', str),
            ('url_ticket', str),
            ('priority', str),
            ('raw_subject', str),
            ('subject', str),
            ('ticket_via', str),
            ('via', str),
            ('tags', str),
            ('id_group', str),
            ('id_ticket_form', str),
            ('id_requester', str),
            ('id_assignee', str),
            ('ids_collaborator', str),
            ('id_brand', str),
            ('id_submitter', str),
            ('status', str),
            ('custom_fields', str),
            ('has_incidents', str),
            ('type', str),
            ('allow_channelback', str),
            ('description', str),
            ('recipient', str),
            ('is_public', str),
            ('ts_created', str),
            ('ts_created_local', str),
            ('ts_updated', str),
            ('ts_load', str)
        ])

        self._move_to_clean_partitioned(
            class_=ZendeskTickets.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
