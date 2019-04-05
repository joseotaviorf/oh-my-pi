from gzip import GzipFile
from io import BytesIO

from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.data_frame_service.data_frame_service import DataFrameService

logger = QuintoAndarLogger('DataFrameJsonService')


class DataFrameJsonService(DataFrameService):

    @logger(exclude='df')
    def __init__(self, df=None):
        super(DataFrameJsonService, self).__init__(df=df)

    @logger
    def to_json_bytes(self, encoding='utf-8', line_break=True):
        gz_body = BytesIO()
        with GzipFile(fileobj=gz_body, mode='w') as fp:
            for row in self.df.iterrows():
                fp.write(row[1].to_json().encode(encoding))
                if line_break:
                    fp.write('\n')

        return gz_body
