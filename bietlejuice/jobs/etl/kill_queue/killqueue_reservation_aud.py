from collections import OrderedDict
from copy import deepcopy

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.kill_queue.killqueue import KillQueue
from bietlejuice.jobs.etl.kill_queue.killqueue_table_enum import KillQueueTableEnum

logger = QuintoAndarLogger('KillQueueReservationAud')


class KillQueueReservationAud(KillQueue):

    def __init__(self, s3_bucket):
        super(KillQueueReservationAud, self).__init__(s3_bucket=s3_bucket)
        self.table_name = KillQueueTableEnum.RESERVATION_AUD.value

    @logger
    def move_data_from_raw_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('rev', str),
            ('rev_type', str),
            ('revend', str),
            ('attempt', str),
            ('is_attempt_mod', str),
            ('mundipagg_token', str),
            ('is_mundipagg_token_mod', str),
            ('status', str),
            ('is_status_mod', str),
            ('id_tenant', str),
            ('value', str),
            ('is_value_mod', str),
            ('id_house', str),
            ('cancellation_reason', str),
            ('is_cancellation_reason_mod', str),
        ])
        c_cols = deepcopy(r_cols)

        self._move_data_from_raw_to_clean(self.table_name, r_cols, c_cols)
