from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.new_etl.asterisk.asterisk_table_enum import AsteriskTableEnum


class AsteriskIVREntries(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.IVR_ENTRIES

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskIVREntries, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data_full(_class=AsteriskIVREntries.CLASS_ENUM)

    @logger
    def data_existence_check(self, bucket_type):
        return self._data_existence_check_full(bucket_type=bucket_type, _class=AsteriskIVREntries.CLASS_ENUM)

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('ivr_id', str),
            ('selection', str),
            ('dest', str),
            ('ivr_ret', str)
        ])

        c_cols = OrderedDict([
            ('ivr_id', int),
            ('selection', str),
            ('destination', str),
            ('ivr_ret', int)
        ])

        self._move_to_clean_full(
            _class=AsteriskIVREntries.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
