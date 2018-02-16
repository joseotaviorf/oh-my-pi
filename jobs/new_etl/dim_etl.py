from qa_python_utils.aws.athena import AthenaClient
from qa_python_utils.default_logger import logger


class DimensionETL(object):

    @logger
    def __init__(self, bucket, now):
        self.bucket = bucket
        self.now = now
        self.athena = AthenaClient(bucket)
