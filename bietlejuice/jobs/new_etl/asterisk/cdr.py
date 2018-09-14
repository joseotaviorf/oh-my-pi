from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.new_etl.asterisk.asterisk_table_enum import AsteriskTableEnum


class AsteriskCDR(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.CDR

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskCDR, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data_partitioned(_class=AsteriskCDR.CLASS_ENUM)

    @logger
    def data_existence_check(self, bucket_type):
        return self._data_existence_check_partitioned(bucket_type=bucket_type, _class=AsteriskCDR.CLASS_ENUM)

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('calldate', str),
            ('clid', str),
            ('src', str),
            ('dst', str),
            ('dcontext', str),
            ('channel', str),
            ('dstchannel', str),
            ('lastapp', str),
            ('lastdata', str),
            ('duration', str),
            ('billsec', str),
            ('disposition', str),
            ('amaflags', str),
            ('accountcode', str),
            ('uniqueid', str),
            ('userfield', str),
            ('did', str),
            ('recordingfile', str),
            ('cnum', str),
            ('cnam', str),
            ('outbound_cnum', str),
            ('outbound_cnam', str),
            ('dst_cnam', str)
        ])

        c_cols = OrderedDict([
            ('call_date', str),
            ('cl_id', str),
            ('src', str),
            ('destination', str),
            ('d_context', str),
            ('channel', str),
            ('dst_channel', str),
            ('last_app', str),
            ('last_data', str),
            ('duration', int),
            ('bill_sec', int),
            ('disposition', str),
            ('ama_flags', int),
            ('account_code', str),
            ('unique_id', str),
            ('user_field', str),
            ('d_id', str),
            ('recording_file', str),
            ('caller_number', str),
            ('caller_name', str),
            ('outbound_caller_number', str),
            ('outbound_caller_name', str),
            ('dst_cnam', str)
        ])

        self._move_to_clean_partitioned(
            _class=AsteriskCDR.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
