from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskTicketFields')


class ZendeskTicketFields(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.TICKET_FIELDS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskTicketFields, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, class_, bucket_type):
        self._upsert_single_partition(bucket_type=bucket_type, class_=ZendeskTicketFields.CLASS_ENUM)

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_ticket_fields', str),
            ('title', str),
            ('description', str),
            ('agent_description', str),
            ('url_ticket_fields', str),
            ('raw_title', str),
            ('raw_title_in_portal', str),
            ('raw_description', str),
            ('custom_field_options', str),
            ('is_removable', str),
            ('is_position', str),
            ('is_required', str),
            ('type', str),
            ('is_active', str),
            ('is_collapsed_for_agents', str),
            ('is_visible_in_portal', str),
            ('is_required_in_portal', str),
            ('is_editable_in_portal', str),
            ('is_title_in_portal', str),
            ('ts_created_local', str),
            ('ts_created', str),
            ('ts_updated', str),
            ('ts_load', str)
        ])

        self._move_to_clean_partitioned(
            class_=ZendeskTicketFields.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
