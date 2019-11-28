from abc import abstractmethod, ABC
from datetime import timedelta
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("ZendeskConsumer")


class ZendeskConsumer(ABC):
    @logger
    def __init__(self, zendesk_client, spark_client, execution_date):
        self.zendesk_client = zendesk_client
        self.spark_client = spark_client
        self.start_timestamp = execution_date.strftime("%s")
        self.end_timestamp = (execution_date + timedelta(days=1)).strftime("%s")

    @abstractmethod
    def request_api_and_get_dataframe(self, endpoint):
        raise NotImplementedError()
