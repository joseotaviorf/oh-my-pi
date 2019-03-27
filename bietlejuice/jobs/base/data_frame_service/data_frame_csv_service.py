from io import StringIO

import pandas as pd
from qa_python_utils.default_logger import QuintoAndarLogger

from bietlejuice.jobs.base.data_frame_service.data_frame_service import DataFrameService

logger = QuintoAndarLogger('DataFrameCSVService')


class DataFrameCSVService(DataFrameService):

    @logger(exclude='df')
    def __init__(self, df=None):
        super(DataFrameCSVService, self).__init__(df=df)

    @logger(exclude='csv_content')
    def unicode_to_df(self, csv_content):
        if not isinstance(csv_content, unicode):
            raise TypeError('m=unicode_to_df, msg=csv content must be unicode')

        memory_content = StringIO(csv_content)
        return pd.read_csv(memory_content)
