from collections import OrderedDict
from copy import deepcopy

from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.kill_queue.killqueue import KillQueue
from bietlejuice.jobs.etl.kill_queue.killqueue_table_enum import KillQueueTableEnum

logger = QuintoAndarLogger('KillQueueHouse')


class KillQueueHouse(KillQueue):

    def __init__(self, s3_bucket):
        super(KillQueueHouse, self).__init__(s3_bucket=s3_bucket)
        self.table_name = KillQueueTableEnum.HOUSE.value

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
            ('main_id', str),
            ('street_address', str),
            ('house_number', str),
            ('complement', str),
            ('city', str),
            ('state', str),
            ('reservation_allowed', str),
            ('rent_price', str),
            ('floor', str),
            ('reservation_fee', str),
            ('region_id', str),
            ('owner_id', str)
        ])
        c_cols = deepcopy(r_cols)

        self._move_data_from_raw_to_clean(self.table_name, r_cols, c_cols)
