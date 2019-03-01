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
    def factory(class_, s3_bucket, execution_date):
        class__ = AsteriskFactory.__dispatch_dict(class_)
        if class__ is None:
            raise RuntimeError('m=factory, _class={}, msg=class type not found'.format(class_))

        return class__(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @staticmethod
    def __dispatch_dict(_class):
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
        }.get(_class)
