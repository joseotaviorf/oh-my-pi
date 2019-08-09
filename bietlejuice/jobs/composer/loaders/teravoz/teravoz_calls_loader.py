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

    def __init__(self, api_user, api_pwd, execution_date):

        # extract to day, month and year to create columns in df
        dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")
        self.PARTITIONS["year"] = self.PARTITIONS["year"].format(
            year=execution_date.year
        )
        self.PARTITIONS["month"] = self.PARTITIONS["month"].format(
            month=execution_date.month
        )
        self.PARTITIONS["day"] = self.PARTITIONS["day"].format(day=execution_date.day)

        # convert to br data format recognized by Teravoz API
        strdate = datetime.strftime(dt_execution, "%d-%m-%Y")
        self.PARAMS["date"] = self.PARAMS["date"].format(date=strdate)

        super().__init__(api_user, api_pwd, execution_date)

    @staticmethod
    @logger
    def _create_dataframe_columns_to_partition_table(df, partitions):

        for partition_name, partition_value in partitions.items():
            df = df.withColumn(partition_name, lit(partition_value))

        return df

    @logger
    def request_api_and_get_dataframe(self):

        df = super()._request_api_and_get_dataframe(
            endpoint="calls", params=self.PARAMS
        )
        return df

    @logger
    def load_data_into_datalake(self, df, datalake_layer):

        df = self._create_dataframe_columns_to_partition_table(df, self.PARTITIONS)

        super()._load_data_into_datalake(
            df=df,
            endpoint="calls",
            datalake_layer=datalake_layer,
            partitions=self.PARTITIONS,
        )
