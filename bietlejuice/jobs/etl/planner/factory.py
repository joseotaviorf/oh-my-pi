from bietlejuice.jobs.etl.planner.agent import PlannerAgent
from bietlejuice.jobs.etl.planner.planner_table_enum import PlannerTableEnum
from bietlejuice.jobs.etl.planner.region import PlannerRegion


class PlannerFactory(object):

    @staticmethod
    def factory(_class, s3_bucket, execution_date):
        __class = PlannerFactory.__dispatch_dict(_class)
        if _class is None:
            raise Exception('m=factory, _class={}, msg=class type not found'.format(_class))

        return __class(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            PlannerTableEnum.AGENT: PlannerAgent,
            PlannerTableEnum.REGION: PlannerRegion
        }.get(_class)
