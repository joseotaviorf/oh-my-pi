from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.zendesk.zendesk import Zendesk
from bietlejuice.jobs.etl.zendesk.table_enum import ZendeskTableEnum

logger = QuintoAndarLogger('ZendeskUsers')


class ZendeskUsers(Zendesk):
    CLASS_ENUM = ZendeskTableEnum.USERS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(ZendeskUsers, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def upsert_single_partition(self, class_, bucket_type):
        self._upsert_single_partition(bucket_type=bucket_type,
                                      class_=ZendeskUsers.CLASS_ENUM,
                                      integration_name='zendesk_users')

    @logger
    def move_to_clean(self, class_, bucket_type):
        r_cols = OrderedDict([
            ('id_user', str),
            ('is_active', str),
            ('alias', str),
            ('details', str),
            ('email', str),
            ('phone', str),
            ('name', str),
            ('notes', str),
            ('url_user', str),
            ('chat_only', str),
            ('id_custom_role', str),
            ('id_default_group', str),
            ('id_external', str),
            ('locale', str),
            ('id_locale', str),
            ('is_moderator', str),
            ('is_only_private_comments', str),
            ('id_organization', str),
            ('is_permanently_deleted', str),
            ('is_report_csv', str),
            ('is_restricted_agent', str),
            ('role', str),
            ('role_type', str),
            ('is_shared', str),
            ('is_shared_agent', str),
            ('is_shared_phone_number', str),
            ('signature', str),
            ('is_suspended', str),
            ('tags', str),
            ('ticket_restriction', str),
            ('time_zone', str),
            ('is_two_factor_auth_enabled', str),
            ('user_fields', str),
            ('is_verified', str),
            ('ts_last_login', str),
            ('ts_created', str),
            ('ts_created_local', str),
            ('ts_updated', str),
            ('ts_load', str),
        ])

        self._move_to_clean_partitioned(
            class_=ZendeskUsers.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
