from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.teravoz import TeravozConsumer

logger = QuintoAndarLogger("TeravozReportsConsumer")


class TeravozReportsConsumer(TeravozConsumer):
    
    UTC_HOUR_START = "T03:00:00.000Z"
    UTC_HOUR_END = "T02:59:59.999Z"

    @logger
    def __init__(self, api_user, api_pwd, execution_date):
        super().__init__(api_user, api_pwd, execution_date)

    @logger
    def __build_api_params(self):

        list_queue_numbers = super()._get_queue_numbers()

        list_queues = []
        for queue in list_queue_numbers:
            list_queues.append(queue.number)

        params = {
            "queue_number": "&queues[]=".join(list_queues),
            "start_date": self.execution_date + self.UTC_HOUR_START,
            "end_date": datetime.strftime(
                self.dt_execution + timedelta(days=1), "%Y-%m-%d"
            )
            + self.UTC_HOUR_END,
        }

        return params

    @logger
    def request_api_and_get_dataframe(self, endpoint):

        # build params to call API
        params = self.__build_api_params()
        endpoint = endpoint.replace("-", "_")

        df = super().request_api_and_get_dataframe(endpoint, params)

        return df
