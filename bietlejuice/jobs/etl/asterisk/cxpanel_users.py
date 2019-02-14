from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.etl.asterisk.asterisk_table_enum import AsteriskTableEnum

logger = QuintoAndarLogger('AsteriskCXPanelUsers')


class AsteriskCXPanelUsers(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.CXPANEL_USERS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskCXPanelUsers, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data_full(_class=AsteriskCXPanelUsers.CLASS_ENUM)

    @logger
    def data_existence_check(self, bucket_type):
        return self._data_existence_check_full(bucket_type=bucket_type, _class=AsteriskCXPanelUsers.CLASS_ENUM)

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('cxpanel_user_id', str),
            ('user_id', str),
            ('display_name', str),
            ('peer', str),
            ('add_extension', str),
            ('full', str),
            ('add_user', str),
            ('hashed_password', str),
            ('initial_password', str),
            ('auto_answer', str),
            ('parent_user_id', str),
            ('password_dirty', str)
        ])

        c_cols = OrderedDict([
            ('cxpanel_user_id', str),
            ('user_id', str),
            ('display_name', str),
            ('peer', str),
            ('add_extension', str),
            ('full', str),
            ('add_user', str),
            ('hashed_password', str),
            ('initial_password', str),
            ('auto_answer', str),
            ('parent_user_id', str),
            ('password_dirty', str)
        ])

        self._move_to_clean_full(
            _class=AsteriskCXPanelUsers.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
