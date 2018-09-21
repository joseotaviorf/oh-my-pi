from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.new_etl.asterisk.asterisk_table_enum import AsteriskTableEnum


class AsteriskQueuesConfig(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.QUEUES_CONFIG

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskQueuesConfig, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data_full(_class=AsteriskQueuesConfig.CLASS_ENUM)

    @logger
    def data_existence_check(self, bucket_type):
        return self._data_existence_check_full(bucket_type=bucket_type, _class=AsteriskQueuesConfig.CLASS_ENUM)

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('extension', str),
            ('descr', str),
            ('grppre', str),
            ('alertinfo', str),
            ('ringing', str),
            ('maxwait', str),
            ('password', str),
            ('ivr_id', str),
            ('dest', str),
            ('cwignore', str),
            ('queuewait', str),
            ('use_queue_context', str),
            ('togglehint', str),
            ('qnoanswer', str),
            ('callconfirm', str),
            ('callconfirm_id', str),
            ('qregex', str),
            ('agentannounce_id', str),
            ('joinannounce_id', str),
            ('monitor_type', str),
            ('monitor_heard', str),
            ('monitor_spoken', str),
            ('callback_id', str)
        ])

        c_cols = OrderedDict([
            ('extension', str),
            ('description', str),
            ('grppre', str),
            ('alert_info', str),
            ('ringing', str),
            ('max_wait', str),
            ('password', str),
            ('ivr_id', str),
            ('destination', str),
            ('cw_ignore', str),
            ('queue_wait', str),
            ('use_queue_context', str),
            ('toggle_hint', str),
            ('q_no_answer', str),
            ('call_confirm', str),
            ('call_confirm_id', str),
            ('q_regex', str),
            ('agent_announce_id', str),
            ('join_announce_id', str),
            ('monitor_type', str),
            ('monitor_heard', str),
            ('monitor_spoken', str),
            ('callback_id', str)
        ])

        self._move_to_clean_full(
            _class=AsteriskQueuesConfig.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
