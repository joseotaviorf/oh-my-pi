from quintoandar_logger import QuintoAndarLogger
from quintoandar_teravoz_client import TeravozClient
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from datetime import datetime, timedelta, date
from pyspark.sql.functions import lit

logger = QuintoAndarLogger("TeravozLoader")


class TeravozLoader:

    # source to create folders and schemas
    SOURCE = "teravoz"

    # spark instances
    sc = BaseSparkContext.sc
    spark = BaseSparkContext.spark
    sqlContext = BaseSparkContext.sqlContext

    @logger
    def __init__(self, api_user, api_pwd):
        # api_instance
        self.api_instance = TeravozClient(api_user=api_user, api_pwd=api_pwd)

    @logger
    def request_api_and_get_data(self, endpoint, **params):

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
        return json().data

    @logger
    def _build_s3_path_to_load(self, df, datalake_layer, endpoint, partitions=None):
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
            list_partitions = []
            partitions_path = ""
            for partition_name, partition_value in partitions.items():
                partitions_path += "/{}={}".format(partition_name, partition_value)
                list_partitions.append("{}={}".format(partition_name, partition_value))
                df = df.withColumn(partition_name, lit(partition_value))

            self.__write_data_to_s3(df, s3_path, endpoint, partitions, partitions_path)
            self._create_partition_table(
                endpoint, (s3_path + partitions_path), list_partitions
            )
            # self.spark.sql("MSCK REPAIR TABLE {}.{}".format(self.SOURCE, endpoint))

        else:
            print("Não tem partições")
            self.__write_data_to_s3(df, s3_path, endpoint)

    @logger
    def __write_data_to_s3(
        self, df, s3_path, endpoint, partitions=None, partitions_path=None
    ):

        """
          load request from endpoint to s3 without partitions and
          if exists the file, overwrite it.
        """

        # dataframe to json
        df_write = (
            df.write.mode("overwrite")
            .option("compression", "gzip")
            .format("json")
            .option("path", s3_path if not partitions else (s3_path + partitions_path))
        )

        # create database if not exists in spark catalog
        self.spark.sql("create database if not exists {}".format(self.SOURCE))

        if endpoint not in self.sqlContext.tableNames(dbName=self.SOURCE):
            logger.info(
                "m=__write_data_to_s3, db={}, table_name={},".format(
                    self.SOURCE, endpoint
                )
                + "table does not exist in db, creating new..."
            )

            if partitions:
                df_write.partitionBy(*partitions.keys())

            df_write.saveAsTable("{}.{}".format(self.SOURCE, endpoint))
        else:
            df_write.save()
            spark.sql("REFRESH TABLE {}.{}".format(self.SOURCE, endpoint))

    @logger
    def _create_partition_table(self, endpoint, s3_path, list_partitions):
        print(s3_path)
        self.spark.sql(
            "ALTER TABLE {}.{} ".format(self.SOURCE, endpoint)
            + "ADD IF NOT EXISTS PARTITION ({}) ".format(",".join(list_partitions))
            + "LOCATION '{}'".format(s3_path)
        )

    @logger
    def load_data_into_datalake(self, args):
        (endpoint, params) = args
        # params.format(execution_date=EXECUTION_DATE)
        json_data = self.request_api_and_get_data(endpoint, **params)

        if endpoint in json_data.keys():
            key = endpoint
        elif "list" in json_data.keys():
            key = "list"
        elif "result" in json_data.keys():
            key = "result"

        jsonRDD = self.sc.parallelize(json_data[key])
        df = self.sqlContext.read.option("multiLine", "true").json(jsonRDD)

        if params:
            partitions = {
                "year": datetime.strftime(EXECUTION_DATE, "%Y"),
                "month": datetime.strftime(EXECUTION_DATE, "%m"),
                "day": datetime.strftime(EXECUTION_DATE, "%d"),
            }
            self._build_s3_path_to_load(df, "raw", endpoint, partitions)

        else:
            self._build_s3_path_to_load(df, "raw", endpoint)
            print("Não tem parâmetros")
