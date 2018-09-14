from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.new_etl.asterisk.asterisk_table_enum import AsteriskTableEnum
from bietlejuice.jobs.new_etl.asterisk.cdr import AsteriskCDR
from bietlejuice.jobs.new_etl.asterisk.cxpanel_queues import AsteriskCXPanelQueues
from bietlejuice.jobs.new_etl.asterisk.cxpanel_users import AsteriskCXPanelUsers
from bietlejuice.jobs.new_etl.asterisk.devices import AsteriskDevices
from bietlejuice.jobs.new_etl.asterisk.ivr_details import AsteriskIVRDetails
from bietlejuice.jobs.new_etl.asterisk.ivr_entries import AsteriskIVREntries
from bietlejuice.jobs.new_etl.asterisk.queues_config import AsteriskQueuesConfig
from bietlejuice.jobs.new_etl.asterisk.queues_details import AsteriskQueuesDetails
from bietlejuice.jobs.new_etl.asterisk.users import AsteriskUsers


class AsteriskFactory(object):
    @staticmethod
    def factory(_class, s3_bucket, execution_date):
        __class = AsteriskFactory.__dispatch_dict(_class)
        if _class is None:
            _logger.error('m=factory, _class={}, msg=class type not found'.format(_class))
            raise Exception

        return __class(
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
