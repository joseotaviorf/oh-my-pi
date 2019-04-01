from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.etl.asterisk.asterisk_table_enum import AsteriskTableEnum

logger = QuintoAndarLogger('AsteriskCallsDetails')


class AsteriskCallsDetails(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.CALLS_DETAILS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskCallsDetails, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id_call', str),
            ('call_source_number', str),
            ('call_destination_number', str),
            ('id_ura', str),
            ('ts_start_ura', str),
            ('ts_end_ura', str),
            ('is_URA_HELP_solved', str),
            ('id_queue', str),
            ('id_caller', str),
            ('ts_start_queue', str),
            ('ts_end_queue', str),
            ('id_attendance', str),
            ('ts_start_attendance', str),
            ('ts_end_attendance', str),
            ('sec_time_duration_ura', str),
            ('sec_time_duration_queue', str),
            ('sec_time_duration_attendance', str)
        ])

        c_cols = OrderedDict([
            ('id_call', str),
            ('call_source_number', str),
            ('call_destination_number', str),
            ('id_ura', str),
            ('ts_start_ura', str),
            ('ts_end_ura', str),
            ('is_URA_HELP_solved', str),
            ('id_queue', str),
            ('id_caller', str),
            ('ts_start_queue', str),
            ('ts_end_queue', str),
            ('id_attendance', str),
            ('ts_start_attendance', str),
            ('ts_end_attendance', str),
            ('sec_time_duration_ura', str),
            ('sec_time_duration_queue', str),
            ('sec_time_duration_attendance', str)
        ])

        self._move_to_clean_partitioned(
            class_=AsteriskCallsDetails.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=c_cols
        )
