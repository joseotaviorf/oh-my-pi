from ordereddict import OrderedDict
from qa_python_utils.default_logger import logger

from bietlejuice.jobs.new_etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.new_etl.asterisk.asterisk_table_enum import AsteriskTableEnum


class AsteriskDevices(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.DEVICES

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskDevices, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def extract_and_load_data(self):
        self._extract_and_load_data_full(_class=AsteriskDevices.CLASS_ENUM)

    @logger
    def data_existence_check(self, bucket_type):
        return self._data_existence_check_full(bucket_type=bucket_type, _class=AsteriskDevices.CLASS_ENUM)

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('tech', str),
            ('dial', str),
            ('devicetype', str),
            ('user', str),
            ('description', str),
            ('emergency_cid', str)
        ])

        c_cols = OrderedDict([
            ('id', str),
            ('tech', str),
            ('dial', str),
            ('device_type', str),
            ('user_id', str),
            ('description', str),
            ('emergency_cid', str)
        ])

        self._move_to_clean_full(
            _class=AsteriskDevices.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
