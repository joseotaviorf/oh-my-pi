from bietlejuice.jobs.etl.crm.tasks.closing import CRMTasksClosing
from bietlejuice.jobs.etl.crm.tasks.credit import CRMTasksCredit
from bietlejuice.jobs.etl.crm.tasks.crm_tasks_table_enum import CRMTasksTableEnum
from bietlejuice.jobs.etl.crm.tasks.inspection import CRMTasksInspection
from bietlejuice.jobs.etl.crm.tasks.lead import CRMTasksLead
from bietlejuice.jobs.etl.crm.tasks.offboarding import CRMTasksOffboarding
from bietlejuice.jobs.etl.crm.tasks.onboarding_tenant import CRMTasksOnboardingTenant
from bietlejuice.jobs.etl.crm.tasks.payment import CRMTasksPayment
from bietlejuice.jobs.etl.crm.tasks.photo_job import CRMTasksPhotoJob
from bietlejuice.jobs.etl.crm.tasks.repair import CRMTasksRepair
from bietlejuice.jobs.etl.crm.tasks.ungrouped_manual import CRMTasksUngroupedManual
from bietlejuice.jobs.etl.crm.tasks.visit import CRMTasksVisit


class CRMTasksFactory(object):

    @staticmethod
    def factory(class_, s3_bucket, mongo_client_uri, execution_date):
        if class_ is None:
            raise ValueError('m=factory, class_={}, msg=invalid class'.format(class_))

        _class = CRMTasksFactory._dispatch_dict(class_)
        if _class is None:
            raise RuntimeError('m=factory, class_={}, msg=class type not found'.format(class_))

        return _class(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @staticmethod
    def _dispatch_dict(class_):
        return {
            CRMTasksTableEnum.CREDIT: CRMTasksCredit,
            CRMTasksTableEnum.VISIT: CRMTasksVisit,
            CRMTasksTableEnum.CLOSING: CRMTasksClosing,
            CRMTasksTableEnum.ONBOARDING_TENANT: CRMTasksOnboardingTenant,
            CRMTasksTableEnum.PAYMENT: CRMTasksPayment,
            CRMTasksTableEnum.INSPECTION: CRMTasksInspection,
            CRMTasksTableEnum.LEAD: CRMTasksLead,
            CRMTasksTableEnum.PHOTO_JOB: CRMTasksPhotoJob,
            CRMTasksTableEnum.REPAIR: CRMTasksRepair,
            CRMTasksTableEnum.UNGROUPED_MANUAL: CRMTasksUngroupedManual,
            CRMTasksTableEnum.OFFBOARDING: CRMTasksOffboarding
        }.get(class_)
