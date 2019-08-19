from bietlejuice.jobs.composer.loaders.teravoz import TeravozLoader
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql.functions import lit
from datetime import datetime
from collections import OrderedDict


logger = QuintoAndarLogger("TeravozCallsLoader")


class TeravozCallsLoader(TeravozLoader):

    PARTITIONS = OrderedDict(
        [("year", "{year}"), ("month", "{month}"), ("day", "{day}")]
    )

    PARAMS = {"date": "{date}"}

    def __init__(self, api_user, api_pwd, environment, execution_date):

        super().__init__(api_user, api_pwd, environment, execution_date)
        # extract to day, month and year to create columns in df
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        self.PARTITIONS["year"] = self.PARTITIONS["year"].format(year=dt_execution.year)
        self.PARTITIONS["month"] = self.PARTITIONS["month"].format(
            month=dt_execution.month
        )
        self.PARTITIONS["day"] = self.PARTITIONS["day"].format(day=dt_execution.day)

        # convert to br data format recognized by Teravoz API
        br_date_format = datetime.strftime(dt_execution, "%d-%m-%Y")
        self.PARAMS["date"] = self.PARAMS["date"].format(date=br_date_format)

    @staticmethod
    @logger
    def _create_dataframe_columns_to_partition_table(df, partitions):

        for partition_name, partition_value in partitions.items():
            df = df.withColumn(partition_name, lit(partition_value))

        return df

    @logger
    def request_api_and_get_dataframe(self, endpoint):

        df = super().request_api_and_get_dataframe(
            endpoint=endpoint, params=self.PARAMS
        )
        return df

    @logger
    def load_data_into_datalake(self, df, table_name, datalake_layer):

        df = self._create_dataframe_columns_to_partition_table(df, self.PARTITIONS)

        super().load_data_into_datalake(
            df=df,
            table_name=table_name,
            datalake_layer=datalake_layer,
            partitions=self.PARTITIONS,
        )
