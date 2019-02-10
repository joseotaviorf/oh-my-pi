from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.kill_queue.killqueue_house import KillQueueHouse
from bietlejuice.jobs.etl.kill_queue.killqueue_rent_flow import KillQueueRentFlow
from bietlejuice.jobs.etl.kill_queue.killqueue_reservation import KillQueueReservation
from bietlejuice.jobs.etl.kill_queue.killqueue_reservation_aud import KillQueueReservationAud
from bietlejuice.jobs.etl.kill_queue.killqueue_table_enum import KillQueueTableEnum

logger = QuintoAndarLogger('KillQueueFactory')


class KillQueueFactory(object):
    @staticmethod
    def get_object(table, s3_bucket):
        if not table:
            raise ValueError('m=get_object, table={}, msg=table cannot be none'.format(table))
        _class = KillQueueFactory.__dispatch_dict(table)
        if not _class:
            raise RuntimeError('m=get_object, table={}, msg=class type not found'.format(table))

        return _class(
            s3_bucket=s3_bucket,
        )

    @staticmethod
    def __dispatch_dict(table):
        return {
            KillQueueTableEnum.HOUSE: KillQueueHouse,
            KillQueueTableEnum.RESERVATION: KillQueueReservation,
            KillQueueTableEnum.RESERVATION_AUD: KillQueueReservationAud,
            KillQueueTableEnum.RENT_FLOW: KillQueueRentFlow,
        }.get(table)
