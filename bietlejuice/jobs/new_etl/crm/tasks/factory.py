from bietlejuice.jobs.new_etl.crm.tasks.credit import CRMTasksCredit
from bietlejuice.jobs.new_etl.crm.tasks.crm_tasks_table_enum import CRMTasksTableEnum
from bietlejuice.jobs.new_etl.crm.tasks.visit import CRMTasksVisit


class CRMTasksFactory(object):

    @staticmethod
    def factory(_class, s3_bucket, mongo_client_uri, execution_date):
        __class = CRMTasksFactory.__dispatch_dict(_class)
        if _class is None:
            raise Exception('m=factory, _class={}, msg=class type not found'.format(_class))

        return __class(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            CRMTasksTableEnum.CREDIT: CRMTasksCredit,
            CRMTasksTableEnum.VISIT: CRMTasksVisit
        }.get(_class)
