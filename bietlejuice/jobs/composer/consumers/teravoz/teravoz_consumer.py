from datetime import datetime
from quintoandar_logger import QuintoAndarLogger
from quintoandar_teravoz_client import TeravozClient

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("TeravozConsumer")

# spark instances
sc = BaseSparkContext.sc
sqlContext = BaseSparkContext.sqlContext
spark = BaseSparkContext.spark


class TeravozConsumer:
    @logger
    def __init__(self, api_user, api_pwd, execution_date):
        self.api_instance = TeravozClient(api_user=api_user, api_pwd=api_pwd)
        self.execution_date = execution_date
        self.dt_execution = datetime.strptime(self.execution_date, "%Y-%m-%d")

    @staticmethod
    @logger
    def _get_queue_numbers():
        """
            This method is required for report tables, because
            their endpoints parametrize the queue number.
        """
        df = spark.sql("select number from datalake_teravoz_raw.queues")
        return df.select("number").collect()

    @logger
    def request_api_and_get_dataframe(self, endpoint, params={}):
        """
            endpoint: endpoint ..@teravoz.com.br/{endpoint}
            params: if exists is expected the format:
                  {
                    "param_name1": "param_value1",
                    "param_name2": "param_value2"
                  }
            return: data in json format
        """

        response = getattr(self.api_instance, endpoint)(**params).get()
        response_list = []

        for page in response().pages():
            json_data = page().data

            if endpoint in json_data.keys():
                key = endpoint
            elif "list" in json_data.keys():
                key = "list"
            elif "result" in json_data.keys():
                key = "result"
            elif "queues" in json_data.keys():
                key = "queues"

            response_list.append(json_data[key])

        jsonRDD = sc.parallelize(response_list, 1)
        df = sqlContext.read.option("multiLine", "true").json(jsonRDD)

        return df
