from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.api_consumers.teravoz.teravoz_consumer import (
    TeravozConsumer,
)

logger = QuintoAndarLogger("TeravozReportAgentStatusConsumer")


class TeravozReportAgentStatusConsumer(TeravozConsumer):
    UTC_HOUR = "T03:00:00.000Z"

    @logger
    def __init__(self, teravoz_client, spark_client, execution_date):
        super().__init__(teravoz_client, spark_client, execution_date)

    @logger
    def __build_api_params(self):

        params = {
            "queue_number": "",
            "start_date": self.execution_date + self.UTC_HOUR,
            "end_date": datetime.strftime(
                self.dt_execution + timedelta(days=1), "%Y-%m-%d"
            )
            + self.UTC_HOUR,
        }

        return params

    @logger
    def request_api_and_get_dataframe(self, endpoint):

        endpoint = endpoint.replace("-", "_")
        response_list = []
        list_queue_numbers = super()._get_queue_numbers()

        # build params to call API
        params = self.__build_api_params()

        for queue in list_queue_numbers:
            params["queue_number"] = queue.number
            response = getattr(self.teravoz_client, endpoint)(**params).get()

            for page in response().pages():
                json_data = page().data
                if isinstance(json_data["result"], list):
                    for elem in json_data["result"]:
                        response_list.append(elem)

        df = self.spark_client.create_dataframe(response_list)

        return df
