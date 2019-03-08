from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.asterisk.asterisk_table_enum import AsteriskTableEnum
from bietlejuice.jobs.etl.asterisk.cdr import AsteriskCDR
from bietlejuice.jobs.etl.asterisk.cxpanel_queues import AsteriskCXPanelQueues
from bietlejuice.jobs.etl.asterisk.cxpanel_users import AsteriskCXPanelUsers
from bietlejuice.jobs.etl.asterisk.devices import AsteriskDevices
from bietlejuice.jobs.etl.asterisk.ivr_details import AsteriskIVRDetails
from bietlejuice.jobs.etl.asterisk.ivr_entries import AsteriskIVREntries
from bietlejuice.jobs.etl.asterisk.queues_config import AsteriskQueuesConfig
from bietlejuice.jobs.etl.asterisk.queues_details import AsteriskQueuesDetails
from bietlejuice.jobs.etl.asterisk.users import AsteriskUsers

logger = QuintoAndarLogger('AsteriskFactory')


class AsteriskFactory(object):
    @staticmethod
    def factory(entity, s3_bucket, execution_date):
        if entity is None:
            raise ValueError('m=factory, class_={}, msg=entity cannot be None')
        class_ = AsteriskFactory.__dispatch_dict(entity)
        if class_:
            return class_(
                s3_bucket=s3_bucket,
                execution_date=execution_date)
        else:
            raise RuntimeError('m=factory, entity={}, msg=class type for entity not found'.format(entity))

    @staticmethod
    def __dispatch_dict(entity):
        return {
            AsteriskTableEnum.IVR_DETAILS: AsteriskIVRDetails,
            AsteriskTableEnum.IVR_ENTRIES: AsteriskIVREntries,
            AsteriskTableEnum.USERS: AsteriskUsers,
            AsteriskTableEnum.DEVICES: AsteriskDevices,
            AsteriskTableEnum.QUEUES_CONFIG: AsteriskQueuesConfig,
            AsteriskTableEnum.QUEUES_DETAILS: AsteriskQueuesDetails,
            AsteriskTableEnum.CXPANEL_QUEUES: AsteriskCXPanelQueues,
            AsteriskTableEnum.CXPANEL_USERS: AsteriskCXPanelUsers,
            AsteriskTableEnum.CDR: AsteriskCDR,
        }.get(entity)
