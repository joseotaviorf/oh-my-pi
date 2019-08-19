from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.loaders.teravoz import TeravozLoader

from datetime import datetime, timedelta
from collections import OrderedDict

logger = QuintoAndarLogger("TeravozAgentPerformance")

spark = BaseSparkContext.spark


class TeravozAgentPerformanceLoader(TeravozLoader):

    PARAMS = {
        "queue_number": "{queue_number_list}",
        "start_date": "{start_date}",
        "end_date": "{end_date}",
    }

    PARTITIONS = OrderedDict(
        [("year", "{year}"), ("month", "{month}"), ("day", "{day}")]
    )

    @logger
    def __init__(self, api_user, api_pwd, environment, execution_date):
        super().__init__(api_user, api_pwd, environment, execution_date)

        self.PARAMS["start_date"] = self.PARAMS["start_date"].format(
            start_date=execution_date
        )

        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        self.PARAMS["end_date"] = self.PARAMS["end_date"].format(
            end_date=datetime.strftime(dt_execution + timedelta(days=1), "%Y-%m-%d")
        )

        self.PARTITIONS["year"] = self.PARTITIONS["year"].format(year=dt_execution.year)
        self.PARTITIONS["month"] = self.PARTITIONS["month"].format(
            month=dt_execution.month
        )
        self.PARTITIONS["day"] = self.PARTITIONS["day"].format(day=dt_execution.day)

    @staticmethod
    @logger
    def get_queue_numbers():
        df = spark.sql("select number from datalake_teravoz_raw.queues")
        return df.select("number").collect()

    @logger
    def request_api_and_get_dataframe(self, endpoint):

        list_queue_numbers = self.get_queue_numbers()

        list_queues = []
        for queue in list_queue_numbers:
            list_queues.append(queue.number)

        self.PARAMS["queue_number"] = self.PARAMS["queue_number"].format(
            queue_number_list="&queues[]=".join(list_queues)
        )

        df = super().request_api_and_get_dataframe(
            endpoint=endpoint, params=self.PARAMS
        )

        return df

    @logger
    def load_data_into_datalake(self, df, table_name, datalake_layer):
        df = super()._create_dataframe_columns_to_partition_table(df, self.PARTITIONS)

        super().load_data_into_datalake(
            df=df,
            table_name=table_name,
            datalake_layer=datalake_layer,
            partitions=self.PARTITIONS,
        )
