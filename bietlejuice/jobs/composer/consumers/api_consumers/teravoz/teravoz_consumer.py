from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("TeravozConsumer")


class TeravozConsumer:
    # todo: this class and its children are using the spark_client to return Spark
    #  DataFrames and to query our datalake. Check if we want to maintain this. The
    #  ideal scenario would be to only have a teravoz_client dependency to get the
    #  data from the API, however, the current implementation depends on a datalake
    #  query too.
    @logger
    def __init__(self, teravoz_client, spark_client, execution_date):
        self.teravoz_client = teravoz_client
        self.spark_client = spark_client
        self.execution_date = execution_date
        self.dt_execution = datetime.strptime(self.execution_date, "%Y-%m-%d")

    @logger
    def _get_queue_numbers(self):
        """
            This method is required for report tables, because
            their endpoints parametrize the queue number.
        """
        query = """
            select number from datalake_teravoz_raw.queues
            where year={year} and month={month} and day={day}
        """.format(
            year=self.dt_execution.year,
            month=self.dt_execution.month,
            day=self.dt_execution.day,
        )
        df = self.spark_client.get_records(query)

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

        response = getattr(self.teravoz_client, endpoint)(**params).get()
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

            if isinstance(json_data[key], list):
                for elem in json_data[key]:
                    response_list.append(elem)

        df = self.spark_client.create_dataframe(response_list)

        return df
