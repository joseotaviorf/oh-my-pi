from quintoandar_logger import QuintoAndarLogger
from quintoandar_teravoz_client import TeravozClient
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from datetime import datetime, timedelta, date

logger = QuintoAndarLogger("TeravozLoader")


class TeravozLoader:

    # source to create folders and schemas
    SOURCE = "teravoz"

    # spark instances
    sc = BaseSparkContext.sc
    spark = BaseSparkContext.spark
    sqlContext = BaseSparkContext.sqlContext

    @logger
    def __init__(self, api_user, api_pwd, execution_date):
        # api_instance
        self.api_instance = TeravozClient(api_user=api_user, api_pwd=api_pwd)
        self.execution_date = execution_date

    @logger
    def _request_api_and_get_dataframe(self, endpoint, params):

        """
            endpoint: endpoint ..@teravoz.com.br/{endpoint}
            params: if exists, it's expected the format:
                  {
                    "param_name1": "param_value1",
                    "param_name2": "param_value2"
                  }
            return: data in json format
        """

        json = getattr(self.api_instance, endpoint)(**params).get()
        json_data = json().data

        if endpoint in json_data.keys():
            key = endpoint
        elif "list" in json_data.keys():
            key = "list"
        elif "result" in json_data.keys():
            key = "result"

        jsonRDD = self.sc.parallelize(json_data[key])
        df = self.sqlContext.read.option("multiLine", "true").json(jsonRDD)

        return df

    @logger
    def __build_s3_path_to_load(self, datalake_layer, endpoint, partitions=None):
        """
          build s3 path to load the json file including partitions.
        """

        s3_path = "s3://{}/{}_spark/{}/{}".format(
            "5a-datalake",  # to do: replace with ENV var
            datalake_layer,
            self.SOURCE,
            endpoint,
        )

        if partitions:

            for partition_name, partition_value in partitions.items():
                s3_path += "/{}={}".format(partition_name, partition_value)

        return s3_path

    @logger
    def _create_partition_table(self, endpoint, s3_path, list_partitions):

        self.spark.sql(
            "ALTER TABLE {}.{} ".format(self.SOURCE, endpoint)
            + "ADD IF NOT EXISTS PARTITION ({}) ".format(",".join(list_partitions))
            + "LOCATION '{}'".format(s3_path)
        )

    @logger
    def _create_spark_table_and_load_data_to_s3(
        self, df, datalake_layer, endpoint, partitions=None
    ):

        # to create a partitioned table should pass the columns from df (melhorar)
        if partitions:
            if not partitions.keys().issubset(df.columns):
                df = self.add_partitions_columns_in_dataframe(df, partitions)

        # base path to create table
        s3_path = self.__build_s3_path_to_load(datalake_layer, endpoint)

        # dataframe to json
        df_write = (
            df.write.mode("overwrite")
            .option("compression", "gzip")
            .format("json")
            .option("path", s3_path)
        )

        if partitions:
            df_write.partitions(*partitions.keys())

        df_write.saveAsTable("{}.{}".format(self.SOURCE, endpoint))

    @logger
    def _load_data_into_datalake(self, df, endpoint, datalake_layer, partitions=None):

        """
          load request from endpoint to s3 without partitions and
          if exists the file, overwrite it.
        """

        # create database if not exists in spark catalog
        self.spark.sql("create database if not exists {}".format(self.SOURCE))

        if endpoint not in self.sqlContext.tableNames(dbName=self.SOURCE):
            # create spark table and load data
            self.create_spark_table_and_load_data_to_s3(
                datalake_layer, endpoint, partitions
            )

        else:

            # partitioned path to create table
            s3_path = self.__build_s3_path_to_load(datalake_layer, endpoint, partitions)

            # dataframe to json
            df_write = (
                df.write.mode("overwrite")
                .option("compression", "gzip")
                .format("json")
                .option("path", s3_path)
                .save()
            )

            if partitions:
                list_partitions = []
                for partition_name, partition_value in partitions.items():
                    list_partitions.append(
                        "{}={}".format(partition_name, partition_value)
                    )

                self._create_partition_table(endpoint, s3_path, list_partitions)

            spark.sql("REFRESH TABLE {}.{}".format(self.SOURCE, endpoint))
