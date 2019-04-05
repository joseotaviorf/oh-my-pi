from collections import OrderedDict
from qa_python_utils import QuintoAndarLogger
from bietlejuice.jobs.etl.asterisk.asterisk import Asterisk
from bietlejuice.jobs.etl.asterisk.asterisk_table_enum import AsteriskTableEnum

logger = QuintoAndarLogger('AsteriskEvents')


class AsteriskEvents(Asterisk):
    CLASS_ENUM = AsteriskTableEnum.EVENTS

    @logger
    def __init__(self, s3_bucket, execution_date):
        super(AsteriskEvents, self).__init__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @logger
    def move_to_clean(self):
        r_cols = OrderedDict([
            ('id_call', str),
            ('id_phase', str),
            ('phase', str),
            ('name', str),
            ('params', str),
            ('ts_created', str),
            ('ts_load', str)
        ])

        self._move_to_clean_partitioned(
            class_=AsteriskEvents.CLASS_ENUM,
            r_cols=r_cols,
            c_cols=r_cols
        )
