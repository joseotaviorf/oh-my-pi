from bietlejuice.jobs.etl.demand.active_user_sessions import ActiveUserSessionsETL
from bietlejuice.jobs.etl.demand.active_users import ActiveUsersETL
from bietlejuice.jobs.etl.demand.demand_enum import DemandEnum


class DemandFactory(object):

    @staticmethod
    def factory(class_, s3_bucket):
        if class_ is None:
            raise ValueError('m=factory, class_={}, msg=invalid class'.format(class_))

        _class = DemandFactory.__dispatch_dict(class_)
        if _class is None:
            raise RuntimeError('m=factory, class_={}, msg=class type not found'.format(class_))

        return _class(
            s3_bucket=s3_bucket
        )

    @staticmethod
    def __dispatch_dict(class_):
        return {
            DemandEnum.ACTIVE_USER_SESSIONS: ActiveUserSessionsETL,
            DemandEnum.ACTIVE_USERS: ActiveUsersETL
        }.get(class_)
