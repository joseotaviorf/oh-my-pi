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
        __class = KillQueueFactory.__dispatch_dict(table)
        if not __class:
            logger.error('m=get_object, _class={}, msg=class type not found'.format(table))
            raise Exception

        return __class(
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
