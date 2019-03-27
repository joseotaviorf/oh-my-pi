from qa_python_utils.default_logger import QuintoAndarLogger

logger = QuintoAndarLogger('DataFrameService')


class DataFrameService(object):

    @logger(exclude='df')
    def __init__(self, df=None):
        self.df = df

    @logger
    def set_df(self, df):
        self.df = df

    @logger
    def unset_df(self):
        self.df = None
