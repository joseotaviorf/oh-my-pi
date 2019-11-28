from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.api_consumers.zendesk.zendesk_consumer import (
    ZendeskConsumer,
)
from bietlejuice.jobs.composer.service.json_service import JsonService

logger = QuintoAndarLogger("ZendeskChatsConsumer")


class ZendeskChatsConsumer(ZendeskConsumer):
    @logger
    def __init__(self, zendesk_client, spark_client, execution_date):
        super().__init__(zendesk_client, spark_client, execution_date)
        self.params = {"timestamp": self.start_timestamp}

    def request_api_and_get_dataframe(self, endpoint):
        response = getattr(self.zendesk_client, endpoint)(**self.params).get()
        response_list = []

        for page in response().pages():
            json_data = page().data

            if endpoint in json_data.keys():
                key = endpoint

            if isinstance(json_data[key], list):
                for elem in json_data[key]:
                    elem = JsonService().transform_json_terms(elem)
                    response_list.append(elem)

            # check end_time to limit the results to the current execution_date
            if json_data["end_time"] > int(self.end_timestamp):
                break

        df = self.spark_client.create_dataframe(response_list)

        return df
