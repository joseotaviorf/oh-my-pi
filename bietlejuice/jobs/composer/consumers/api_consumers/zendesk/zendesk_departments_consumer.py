from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.api_consumers.zendesk.zendesk_consumer import (
    ZendeskConsumer,
)
from bietlejuice.jobs.composer.services.json_service import JsonService

logger = QuintoAndarLogger("ZendeskDepartmentsConsumer")


class ZendeskDepartmentsConsumer(ZendeskConsumer):
    @logger
    def __init__(self, zendesk_client, spark_client, execution_date):
        super().__init__(zendesk_client, spark_client, execution_date)
        self.params = {"timestamp": self.start_timestamp}

    def request_api_and_get_dataframe(self, endpoint):
        response = getattr(self.zendesk_client, endpoint)().get()
        response_list = []

        json_data = response().data

        for elem in json_data:
            elem = JsonService().transform_json_terms(elem)
            response_list.append(elem)

        df = self.spark_client.create_dataframe(response_list)

        return df
