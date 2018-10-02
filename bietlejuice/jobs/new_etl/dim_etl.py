from qa_python_utils import QuintoAndarLogger
from qa_python_utils.aws.athena import AthenaClient

logger = QuintoAndarLogger('DimensionETL')


class DimensionETL(object):

    @logger
    def __init__(self, bucket, now):
        self.bucket = bucket
        self.now = now
        self.athena = AthenaClient(bucket)
