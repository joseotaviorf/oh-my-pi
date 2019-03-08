from bietlejuice.jobs.etl.planner.agent import PlannerAgent
from bietlejuice.jobs.etl.planner.planner_table_enum import PlannerTableEnum
from bietlejuice.jobs.etl.planner.region import PlannerRegion


class PlannerFactory(object):

    @staticmethod
    def factory(entity, s3_bucket, execution_date):
        if entity is None:
            raise ValueError('m=factory, msg=entity cannot be None'.format(entity))
        class_ = PlannerFactory.__dispatch_dict(entity)

        if not class_:
            raise RuntimeError('m=factory, entity={}, msg=class type for entity not found'.format(entity))

        return class_(
            s3_bucket=s3_bucket,
            execution_date=execution_date
        )

    @staticmethod
    def __dispatch_dict(entity):
        return {
            PlannerTableEnum.AGENT: PlannerAgent,
            PlannerTableEnum.REGION: PlannerRegion
        }.get(entity)
