from collections import OrderedDict
from copy import deepcopy

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.kill_queue.killqueue import KillQueue
from bietlejuice.jobs.etl.kill_queue.killqueue_table_enum import KillQueueTableEnum

logger = QuintoAndarLogger('KillQueueRentFlow')


class KillQueueRentFlow(KillQueue):

    def __init__(self, s3_bucket):
        super(KillQueueRentFlow, self).__init__(s3_bucket=s3_bucket)
        self.table_name = KillQueueTableEnum.RENT_FLOW.value

    @logger
    def extract_data_and_move_to_raw(self):
        self._extract_data_and_move_to_raw(self.table_name)

    @logger
    def move_data_from_raw_to_clean(self):
        r_cols = OrderedDict([
            ('id', str),
            ('created_at', str),
            ('updated_at', str),
            ('version', str),
            ('firestore_id', str),
            ('house_id', str),
            ('tenant_id', str),
            ('status', str),
        ])
        c_cols = deepcopy(r_cols)

        self._move_data_from_raw_to_clean(self.table_name, r_cols, c_cols)
