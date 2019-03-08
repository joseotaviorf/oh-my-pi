from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.kill_queue.killqueue_house import KillQueueHouse
from bietlejuice.jobs.etl.kill_queue.killqueue_rent_flow import KillQueueRentFlow
from bietlejuice.jobs.etl.kill_queue.killqueue_reservation import KillQueueReservation
from bietlejuice.jobs.etl.kill_queue.killqueue_reservation_aud import KillQueueReservationAud
from bietlejuice.jobs.etl.kill_queue.killqueue_table_enum import KillQueueTableEnum

logger = QuintoAndarLogger('KillQueueFactory')


class KillQueueFactory(object):
    @staticmethod
    def factory(entity, s3_bucket):
        if entity is None:
            raise ValueError('m=factory, msg=entity cannot be None')
        class_ = KillQueueFactory.__dispatch_dict(entity)
        if not class_:
            raise RuntimeError('m=factory, entity={}, msg=class type for entity not found'.format(entity))

        return class_(
            s3_bucket=s3_bucket,
        )

    @staticmethod
    def __dispatch_dict(entity):
        return {
            KillQueueTableEnum.HOUSE: KillQueueHouse,
            KillQueueTableEnum.RESERVATION: KillQueueReservation,
            KillQueueTableEnum.RESERVATION_AUD: KillQueueReservationAud,
            KillQueueTableEnum.RENT_FLOW: KillQueueRentFlow,
        }.get(entity)
