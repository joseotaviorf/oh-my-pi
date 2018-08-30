from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.new_etl.asterisk.asterisk_table_enum import AsteriskTableEnum


class AsteriskIVRDetails(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.IVR_DETAILS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskIVRDetails, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data_full(_class=AsteriskIVRDetails.CLASS_ENUM)

    @logger
    def data_existence_check(self, bucket_type):
        return self._data_existence_check_full(bucket_type=bucket_type, _class=AsteriskIVRDetails.CLASS_ENUM)

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('name', str),
            ('description', str),
            ('announcement', str),
            ('directdial', str),
            ('invalid_loops', str),
            ('invalid_retry_recording', str),
            ('invalid_destination', str),
            ('timeout_enabled', str),
            ('invalid_recording', str),
            ('retvm', str),
            ('timeout_time', str),
            ('timeout_recording', str),
            ('timeout_retry_recording', str),
            ('timeout_destination', str),
            ('timeout_loops', str),
            ('timeout_append_announce', str),
            ('invalid_append_announce', str),
            ('timeout_ivr_ret', str),
            ('invalid_ivr_ret', str),
            ('alertinfo', str),
            ('rvolume', str)
        ])

        c_cols = OrderedDict([
            ('id', int),
            ('name', str),
            ('description', str),
            ('announcement', int),
            ('direct_dial', str),
            ('invalid_loops', str),
            ('invalid_retry_recording', str),
            ('invalid_destination', str),
            ('timeout_enabled', str),
            ('invalid_recording', str),
            ('retvm', str),
            ('timeout_time', int),
            ('timeout_recording', str),
            ('timeout_retry_recording', str),
            ('timeout_destination', str),
            ('timeout_loops', str),
            ('timeout_append_announce', int),
            ('invalid_append_announce', int),
            ('timeout_ivr_ret', int),
            ('invalid_ivr_ret', int),
            ('alert_info', str),
            ('r_volume', str)
        ])

        self._move_to_clean_full(
            _class=AsteriskIVRDetails.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
