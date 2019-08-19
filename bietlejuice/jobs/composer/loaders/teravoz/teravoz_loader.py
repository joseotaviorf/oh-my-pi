from quintoandar_logger import QuintoAndarLogger
from quintoandar_teravoz_client import TeravozClient
from bietlejuice.jobs.composer.base.spark import BaseSparkContext


logger = QuintoAndarLogger("TeravozLoader")

# spark instances
sc = BaseSparkContext.sc
spark = BaseSparkContext.spark
sqlContext = BaseSparkContext.sqlContext


class TeravozLoader:
    """
        Generic class that contains methods for all Teravoz tables and requests,
        such as requests to API, load files to s3 and create spark tables.
    """

    # source to create folders and schemas
    SOURCE = "teravoz"

    @logger
    def __init__(self, api_user, api_pwd, environment, execution_date=None):
        # api_instance (temporarily here)
        self.api_instance = TeravozClient(api_user=api_user, api_pwd=api_pwd)
        self.ENV = environment
        self.execution_date = execution_date

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

        json = getattr(self.api_instance, endpoint)(**params).get()
        json_data = json().data

        if endpoint in json_data.keys():
            key = endpoint
        elif "list" in json_data.keys():
            key = "list"
        elif "result" in json_data.keys():
            key = "result"

        jsonRDD = sc.parallelize(json_data[key])
        df = sqlContext.read.option("multiLine", "true").json(jsonRDD)

        return df

    @logger
    def __build_s3_path_to_load(self, datalake_layer, table_name, partitions=None):
        """
          build s3 path to load the json file including partitions.
        """

        s3_path = "s3://5a-datalake-{}/{}/{}/{}".format(
            self.ENV,  # to do: replace with ENV var
            datalake_layer,
            self.SOURCE,
            table_name,
        )

        if partitions:

            for partition_name, partition_value in partitions.items():
                s3_path += "/{}={}".format(partition_name, partition_value)

        return s3_path

    @logger
    def _create_partition_table(self, db_name, table_name, s3_path, list_partitions):
        """
            Add a specific partition to a spark table
        """
        create_partition = (
            "ALTER TABLE {}.{} ".format(db_name, table_name)
            + "ADD IF NOT EXISTS PARTITION ({}) ".format(",".join(list_partitions))
            + "LOCATION '{}'".format(s3_path)
        )

        logger.info(
            "m=_create_partition_table, msg=Executing command: \n {}".format(
                create_partition
            )
        )

        spark.sql(create_partition)
        spark.sql("REFRESH TABLE {}.{}".format(db_name, table_name))

    @logger
    def _create_dataframe_columns_to_partition_table(df, partitions):
        """
            create columns into df that contains the table partitions values,
            the method should be implemented in heiress class
        """
        raise NotImplementedError

    @logger
    def _create_spark_table_and_load_data_to_s3(
        self, df, datalake_layer, db_name, table_name, partitions=None
    ):
        """
            create spark table and database if not exists,
            load files to s3 and create partitions within an existing table
        """

        # verify if the partitions passed are inside the df.
        if partitions and not set(partitions.keys()).issubset(set(df.columns)):
            df = self._create_dataframe_columns_to_partition_table(df, partitions)

        # base path to create table
        s3_path = self.__build_s3_path_to_load(datalake_layer, table_name)

        # dataframe to json
        df_write = (
            df.write.mode("overwrite")
            .option("compression", "gzip")
            .format("json")
            .option("path", s3_path)
        )

        if partitions:
            df_write.partitionBy(*partitions.keys())

        logger.info(
            "m=_create_spark_table_and_load_data_to_s3, msg= creating spark table {}.{}".format(
                db_name, table_name
            )
        )
        df_write.saveAsTable("{}.{}".format(db_name, table_name))

    @staticmethod
    @logger
    def __upload_dataframe_to_s3(df, s3_path):

        logger.info(
            "m=__upload_dataframe_to_s3, msg=save json file in s3 path: {}".format(
                s3_path
            )
        )

        # dataframe to json
        df.write.mode("overwrite").option("compression", "gzip").format("json").option(
            "path", s3_path
        ).save()

    @logger
    def load_data_into_datalake(self, df, table_name, datalake_layer, partitions=None):

        """
          load request from endpoint to s3 without partitions and
          if exists the file, overwrite it.
        """

        db_name = "datalake_{}_{}".format(self.SOURCE, datalake_layer)

        # create database if not exists in spark catalog
        spark.sql("create database if not exists {}".format(db_name))

        if table_name not in sqlContext.tableNames(dbName=db_name):
            # create spark table and load data
            self._create_spark_table_and_load_data_to_s3(
                df, datalake_layer, db_name, table_name, partitions
            )

        else:

            # partitioned path to create table
            s3_path = self.__build_s3_path_to_load(
                datalake_layer, table_name, partitions
            )

            self.__upload_dataframe_to_s3(df, s3_path)

            if partitions:
                list_partitions = []
                for partition_name, partition_value in partitions.items():
                    list_partitions.append(
                        "{}={}".format(partition_name, partition_value)
                    )

            self._create_partition_table(db_name, table_name, s3_path, list_partitions)
