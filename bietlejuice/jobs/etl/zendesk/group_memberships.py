from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskGroupMemberships')


class ZendeskGroupMemberships(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.GROUP_MEMBERSHIPS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskGroupMemberships, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, class_, bucket_type):
        self._upsert_single_partition(bucket_type=bucket_type,
                                      class_=ZendeskGroupMemberships.CLASS_ENUM,
                                      integration_name='zendesk_groups')

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_group_memberships', str),
            ('url_group_memberships', str),
            ('is_default', str),
            ('id_group', str),
            ('id_user', str),
            ('ts_created', str),
            ('ts_created_local', str),
            ('ts_updated', str),
            ('ts_load', str)
        ])

        self._move_to_clean_partitioned(
            class_=ZendeskGroupMemberships.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
