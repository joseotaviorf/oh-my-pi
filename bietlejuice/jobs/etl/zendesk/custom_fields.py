from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskCustomFields')


class ZendeskCustomFields(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.CUSTOM_FIELDS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskCustomFields, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, class_, bucket_type):
        self._upsert_single_partition(bucket_type=bucket_type,
                                      class_=ZendeskCustomFields.CLASS_ENUM,
                                      integration_name='zendesk_custom_fields')

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_ticket', str),
            ('cols', str)
        ])

        self._move_to_clean_partitioned(
            class_=ZendeskCustomFields.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
