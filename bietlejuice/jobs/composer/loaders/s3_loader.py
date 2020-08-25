from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("S3Loader")


class S3Loader:
    """
    Loads SparkDataFrames into S3
    """

    # todo:  check this value and argue the choice
    MAX_RECORDS_PER_FILE = 250000

    @logger(exclude="df")
    def load_full_table(
        self,
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partitions=[],
        **options
    ):
        """
        Loads the content of an Spark DataFrame as a table in S3.

        If the table already exits, this method overwrites the existing data while
        recreates the table with the schema of the DataFrame.
        :param df: a dataframe
        :type df: SparkDataFrame
        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param format_options: the file format options used to save
        :type format_options: str
        :param database_location: location of the database in the object storage
        :type database_location: str
        :param partitions: names of partitioning columns
        :type partitions: list
        :param options: all other string options
        :type options: keyworded, variable-length argument list
        """
        if not df:
            raise ValueError("m=load_full_table, msg=Spark DataFrame is empty")
        s3_path = database_location + table_name
        df_writer = (
            df.write.mode("overwrite")
            .format(format_options)
            .option("maxRecordsPerFile", self.MAX_RECORDS_PER_FILE)
        )
        if partitions:
            df_writer = df_writer.partitionBy(*partitions)

        for op, val in options.items():
            df_writer = df_writer.option(op, val)

        df_writer.save(path=s3_path)

        logger.info(
            "m=load_full_table, table={}.{}, s3_path={}, "
            "msg=loaded table into S3.".format(database_name, table_name, s3_path)
        )

    @logger(exclude="df")
    def load_incremental_table(
        self,
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
        **options
    ):
        """
        Loads the content of an Spark DataFrame into a table in S3 overwriting the
        corresponding partitions.

        This method will only overwrite the data of the partitions values contained in
        the Spark DataFrame. It doesn't refresh the table in the Spark Metastore,
        so you would need to do it later in the caller side if this is your desire.

        The method is only allowed to execute if spark.sql.sources.partitionOverwriteMode
        is set to 'dynamic', if other behaviour is necessary when loading the data,
        the data in S3 need to be deleted manually.

        :param df: a dataframe
        :type df: SparkDataFrame
        :param database_name: the database name
        :type database_name: str
        :param table_name: the table name
        :type table_name: str
        :param format_options: the file format used to save
        :type format_options: str
        :param database_location: location of the database in the object storage
        :type database_location: str
        :param partition_cols: names of partitioning columns
        :type partition_cols: list
        :param options: all other string options
        :type options: keyworded, variable-length argument list
        """

        if not df:
            raise ValueError("m=load_incremental_table, msg=Spark DataFrame is empty")

        # check spark conf
        spark = BaseSparkContext.spark
        partition_overwrite_mode = spark.conf.get(
            "spark.sql.sources.partitionOverwriteMode"
        ).lower()
        if partition_overwrite_mode != "dynamic":
            raise RuntimeError(
                "m=load_incremental_table, spark.sql.sources.partitionOverwriteMode={}, "
                "msg=partitionOverwriteMode have to be configured to 'dynamic'".format(
                    partition_overwrite_mode
                )
            )

        s3_path = database_location + table_name
        df_writer = (
            df.write.mode("overwrite")
            .format(format_options)
            .option("maxRecordsPerFile", self.MAX_RECORDS_PER_FILE)
            .partitionBy(*partition_cols)
        )
        for op, val in options.items():
            df_writer = df_writer.option(op, val)

        df_writer.save(path=s3_path)

        logger.info(
            "m=load_incremental_table, path={}, "
            "partitions={}, msg=loaded partitions successfully".format(
                s3_path, partition_cols
            )
        )
