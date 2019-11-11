from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.api_consumers.teravoz.teravoz_consumer import (
    TeravozConsumer,
)

logger = QuintoAndarLogger("TeravozCallsConsumer")


class TeravozCallsConsumer(TeravozConsumer):
    @logger
    def __init__(self, teravoz_client, spark_client, execution_date):
        super().__init__(teravoz_client, spark_client, execution_date)

    @logger
    def __build_api_params(self):
        # convert data to br format
        br_date_format = datetime.strftime(self.dt_execution, "%d-%m-%Y")
        params = {"date": br_date_format}

        return params

    @logger
    def request_api_and_get_dataframe(self, endpoint):
        # build params to call API
        params = self.__build_api_params()
        df = super().request_api_and_get_dataframe(endpoint, params)

        return df
