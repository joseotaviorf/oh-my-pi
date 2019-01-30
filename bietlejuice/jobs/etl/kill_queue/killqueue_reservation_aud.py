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
    def extract_data_and_move_to_raw(self):
        self._extract_data_and_move_to_raw(self.table_name)

    @logger
    def move_data_from_raw_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('rev', str),
            ('revtype', str),
            ('revend', str),
            ('attempt', str),
            ('attempt_mod', str),
            ('mundipagg_token', str),
            ('mundipagg_token_mod', str),
            ('status', str),
            ('status_mod', str),
            ('tenant_id', str),
            ('value', str),
            ('value_mod', str),
            ('house_id', str),
        ])
        c_cols = deepcopy(r_cols)

        self._move_data_from_raw_to_clean(self.table_name, r_cols, c_cols)
