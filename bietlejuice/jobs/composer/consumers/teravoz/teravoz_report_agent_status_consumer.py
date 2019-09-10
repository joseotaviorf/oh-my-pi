from datetime import datetime, timedelta

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers.teravoz import TeravozConsumer
from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("TeravozReportAgentStatusConsumer")

# spark instances
sc = BaseSparkContext.sc
sqlContext = BaseSparkContext.sqlContext


class TeravozReportAgentStatusConsumer(TeravozConsumer):
    @logger
    def __init__(self, api_user, api_pwd, execution_date):
        super().__init__(api_user, api_pwd, execution_date)

    @logger
    def __build_api_params(self):

        params = {
            "queue_number": "",
            "start_date": self.execution_date,
            "end_date": datetime.strftime(
                self.dt_execution + timedelta(days=1), "%Y-%m-%d"
            ),
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
            response = getattr(self.api_instance, endpoint)(**params).get()

            for page in response().pages():
                json_data = page().data
                response_list.append(json_data["result"])

        jsonRDD = sc.parallelize(response_list, 1)
        df = sqlContext.read.option("multiLine", "true").json(jsonRDD)
        return df
