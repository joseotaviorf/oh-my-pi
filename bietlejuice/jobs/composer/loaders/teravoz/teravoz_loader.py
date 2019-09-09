from pyspark.sql.functions import lit
from datetime import datetime
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext


logger = QuintoAndarLogger("TeravozLoader")

# spark instances
spark = BaseSparkContext.spark
sqlContext = BaseSparkContext.sqlContext


class TeravozLoader:
    """
        Generic class that contains methods for all Teravoz tables.
        From spark dataframe load data into s3
    """

    # source to create folders and schemas
    SOURCE = "teravoz"

    @logger
    def __init__(self, environment, datalake_layer, table_name, execution_date):
        self.env = environment
        self.datalake_layer = datalake_layer
        self.table_name = table_name
        self.execution_date = execution_date

        # Teravoz partitions pattern
        # convert to datetime
        dt_execution = datetime.strptime(self.execution_date, "%Y-%m-%d")

        self.partitions = OrderedDict(
            [
                ("year", str(dt_execution.year)),
                ("month", str(dt_execution.month)),
                ("day", str(dt_execution.day)),
            ]
        )
        self.db_name = "datalake_teravoz_{}".format(datalake_layer)

        # file attributes in s3
        self.file_format = "json" if datalake_layer == "raw" else "parquet"
        self.file_compression = "gzip" if datalake_layer == "raw" else "snappy"

    @logger
    def __build_s3_path_to_load(self, table_exist=False):
        """
          build s3 path to load the json file including partitions.
        """

        s3_path = "s3://5a-datalake-{}/{}/{}/{}".format(
            self.env, self.datalake_layer, self.SOURCE, self.table_name
        )

        if table_exist:
            for partition_name, partition_value in self.partitions.items():
                s3_path += "/{}={}".format(partition_name, partition_value)

        return s3_path

    # after, this method will be into SparkMetastoreService class (temp here)
    @logger
    def _create_partition_table(self, s3_path, list_partitions):
        """
            Add a specific partition to a spark table
        """
        create_partition = (
            "ALTER TABLE {}.{} ".format(self.db_name, self.table_name)
            + "ADD IF NOT EXISTS PARTITION ({}) ".format(",".join(list_partitions))
            + "LOCATION '{}'".format(s3_path)
        )

        logger.info(
            "m=_create_partition_table, msg=Executing command: \n {}".format(
                create_partition
            )
        )

        spark.sql(create_partition)

    @logger
    def _create_dataframe_columns_to_partition_table(self, df):

        for partition_name, partition_value in self.partitions.items():
            df = df.withColumn(partition_name, lit(partition_value))

        return df

    @logger
    def _create_spark_table_and_load_data_to_s3(self, df):
        """
            create spark table and database if not exists,
            load files to s3 and create partitions within an existing table
        """

        # verify if the partitions passed are inside the df.
        if self.partitions and not set(self.partitions.keys()).issubset(
            set(df.columns)
        ):
            df = self._create_dataframe_columns_to_partition_table(df)

        # base path to create table
        s3_path = self.__build_s3_path_to_load(table_exist=False)

        # dataframe to json
        df_write = (
            df.write.mode("overwrite")
            .option("compression", self.file_compression)
            .format(self.file_format)
            .option("path", s3_path)
        )

        df_write.partitionBy(*self.partitions.keys())

        logger.info(
            "m=_create_spark_table_and_load_data_to_s3, msg= creating spark table {}.{}".format(
                self.db_name, self.table_name
            )
        )
        df_write.saveAsTable("{}.{}".format(self.db_name, self.table_name))

    @logger
    def __upload_dataframe_to_s3(self, df, s3_path):

        logger.info(
            "m=__upload_dataframe_to_s3, msg=save json file in s3 path: {}".format(
                s3_path
            )
        )

        # dataframe to json
        df.write.mode("overwrite").option("compression", self.file_compression).format(
            self.file_format
        ).option("path", s3_path).save()

    @logger
    def load_data_into_datalake(self, df):

        """
          load request from endpoint to s3 without partitions and
          if exists the file, overwrite it.
        """

        # create database if not exists in spark catalog
        spark.sql("create database if not exists {}".format(self.db_name))

        # limits the number of partitions in df, consequently the number of files created in s3
        df = df.coalesce(5)

        if self.table_name not in sqlContext.tableNames(dbName=self.db_name):
            # create spark table and load data
            self._create_spark_table_and_load_data_to_s3(df)

        else:

            # partitioned path to create table
            s3_path = self.__build_s3_path_to_load(table_exist=True)

            self.__upload_dataframe_to_s3(df, s3_path)

            list_partitions = []
            for partition_name, partition_value in self.partitions.items():
                list_partitions.append("{}={}".format(partition_name, partition_value))

            self._create_partition_table(s3_path, list_partitions)

            spark.sql("REFRESH TABLE {}.{}".format(self.db_name, self.table_name))
