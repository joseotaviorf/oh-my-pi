from qa_python_utils.default_logger import _logger

from bietlejuice.jobs.new_etl.crm.tasks import CRMTasksCredit


class CRMTasksFactory(object):

    @staticmethod
    def factory(_class, s3_bucket, mongo_client_uri, execution_date):
        __class = CRMTasksFactory.__dispatch_dict(_class)
        if _class is None:
            _logger.error('m=factory, _class={}, msg=class type not found'.format(_class))
            raise Exception

        return __class(
            s3_bucket=s3_bucket,
            mongo_client_uri=mongo_client_uri,
            execution_date=execution_date
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            'credit': CRMTasksCredit
        }.get(_class)
