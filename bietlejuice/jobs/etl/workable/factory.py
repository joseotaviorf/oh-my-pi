from qa_python_utils import QuintoAndarLogger

from bietlejuice.jobs.etl.workable.candidates import WorkableCandidates
from bietlejuice.jobs.etl.workable.jobs import WorkableJobs
from bietlejuice.jobs.etl.workable.members import WorkableMembers

logger = QuintoAndarLogger('WorkableFactory')


class WorkableFactory(object):

    @staticmethod
    def factory(_class, s3_bucket, url_prefix, access_token):
        __class = WorkableFactory.__dispatch_dict(_class.value)
        if _class is None:
            logger.error('m=factory, _class={}, msg=class type not found'.format(_class))
            raise Exception

        return __class(
            s3_bucket=s3_bucket,
            url_prefix=url_prefix,
            access_token=access_token
        )

    @staticmethod
    def __dispatch_dict(_class):
        return {
            'members': WorkableMembers,
            'jobs': WorkableJobs,
            'candidates': WorkableCandidates
        }.get(_class)
