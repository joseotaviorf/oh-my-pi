from collections import OrderedDict
from copy import deepcopy

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.kill_queue.killqueue import KillQueue
from bietlejuice.jobs.etl.kill_queue.killqueue_table_enum import KillQueueTableEnum

logger = QuintoAndarLogger('KillQueueReservation')


class KillQueueReservation(KillQueue):

    def __init__(self, s3_bucket):
        super(KillQueueReservation, self).__init__(s3_bucket=s3_bucket)
        self.table_name = KillQueueTableEnum.RESERVATION.value

    @logger
    def move_data_from_raw_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('ts_created', str),
            ('ts_updated', str),
            ('version', str),
            ('attempt', str),
            ('id_rent_flow', str),
            ('status', str),
            ('id_tenant', str),
            ('value', str),
            ('id_house', str),
            ('mundipagg_token', str),
            ('is_ongoing', str),
            ('cancellation_reason', str)
        ])
        c_cols = deepcopy(r_cols)

        self._move_data_from_raw_to_clean(self.table_name, r_cols, c_cols)
