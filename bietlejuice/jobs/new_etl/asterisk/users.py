from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.new_etl.asterisk.asterisk_table_enum import AsteriskTableEnum


class AsteriskUsers(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.USERS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskUsers, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data_full(_class=AsteriskUsers.CLASS_ENUM)

    @logger
    def data_existence_check(self, bucket_type):
        return self._data_existence_check_full(bucket_type=bucket_type, _class=AsteriskUsers.CLASS_ENUM)

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('extension', str),
            ('password', str),
            ('name', str),
            ('voicemail', str),
            ('ringtimer', str),
            ('noanswer', str),
            ('recording', str),
            ('outboundcid', str),
            ('sipname', str),
            ('noanswer_cid', str),
            ('busy_cid', str),
            ('chanunavail_cid', str),
            ('noanswer_dest', str),
            ('busy_dest', str),
            ('chanunavail_dest', str),
            ('mohclass', str)
        ])

        c_cols = OrderedDict([
            ('extension', str),
            ('password', str),
            ('name', str),
            ('voicemail', str),
            ('ring_timer', int),
            ('no_answer', str),
            ('recording', str),
            ('outbound_cid', str),
            ('sip_name', str),
            ('no_answer_cid', str),
            ('busy_cid', str),
            ('channel_unavailable_cid', str),
            ('no_answer_destination', str),
            ('busy_destination', str),
            ('channel_unavailable_destination', str),
            ('moh_class', str)
        ])

        self._move_to_clean_full(
            _class=AsteriskUsers.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
