from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.kill_queue.killqueue_house import KillQueueHouse
from bietlejuice.jobs.etl.kill_queue.killqueue_rent_flow import KillQueueRentFlow
from bietlejuice.jobs.etl.kill_queue.killqueue_reservation import KillQueueReservation
from bietlejuice.jobs.etl.kill_queue.killqueue_reservation_aud import KillQueueReservationAud
from bietlejuice.jobs.etl.kill_queue.killqueue_table_enum import KillQueueTableEnum

logger = QuintoAndarLogger('KillQueueFactory')


class KillQueueFactory(object):
    @staticmethod
    def factory(class_type, s3_bucket):
        __class = KillQueueFactory.__dispatch_dict(class_type)
        if class_type is None:
            logger.error('m=factory, _class={}, msg=class type not found'.format(class_type))
            raise Exception

        return __class(
            s3_bucket=s3_bucket,
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            KillQueueTableEnum.HOUSE: KillQueueHouse,
            KillQueueTableEnum.RESERVATION: KillQueueReservation,
            KillQueueTableEnum.RESERVATION_AUD: KillQueueReservationAud,
            KillQueueTableEnum.RENT_FLOW: KillQueueRentFlow,
        }.get(_class)
