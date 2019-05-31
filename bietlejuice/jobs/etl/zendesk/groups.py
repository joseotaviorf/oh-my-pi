from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskGroups')


class ZendeskGroups(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.GROUPS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskGroups, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, class_, bucket_type):
        self._upsert_single_partition(bucket_type=bucket_type, class_=ZendeskGroups.CLASS_ENUM)

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_group', str),
            ('url_group', str),
            ('name', str),
            ('is_deleted', str),
            ('ts_created_local', str),
            ('ts_created', str),
            ('ts_updated', str),
            ('ts_load', str),
        ])

        self._move_to_clean_partitioned(
            class_=ZendeskGroups.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
