from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("S3Loader")


class S3Loader:
    """
    Loads SparkDataFrames into S3 while creating (or updating) the corresponding tables
    into the Spark Metastore.

    :param metastore_service: service to interact with the Spark Metastore
    :type metastore_service: SparkMetastoreService
    """

    # todo:  check this value and argue the choice
    MAX_RECORDS_PER_FILE = 250000

    def __init__(self, metastore_service):
        self.metastore_service = metastore_service

    @logger(exclude="df")
    def load_full_table(self, df, table_name, format, partitions=[], **options):
        """
        Loads the content of an Spark DataFrame as a table in S3.

        If the table already exits, this method overwrites the existing data while
        recreates the table with the schema of the DataFrame.
        :param df: an Spark DataFrame
        :type df: SparkDataFrame
        :param table_name: the table name
        :type table_name: str
        :param format: the file format used to save
        :type format: str
        :param partitions: names of partitioning columns
        :type partitions: list
        :param options: all other string options
        :type options: keyworded, variable-length argument list
        """
        if not df:
            raise ValueError("m=load_full_table, msg=Spark DataFrame is empty")

        s3_path = self.metastore_service.db_path + table_name
        mod_df = (
            df.write.mode("overwrite")
            .format(format)
            .option("maxRecordsPerFile", self.MAX_RECORDS_PER_FILE)
        )
        if partitions:
            mod_df = mod_df.partitionBy(*partitions)
        for op, val in options.items():
            mod_df = mod_df.option(op, val)

        mod_df.option("path", s3_path).saveAsTable(
            "{}.{}".format(self.metastore_service.db, table_name)
        )

        logger.info(
            "m=load_full_table, table={}.{}, s3_path={}, "
            "msg=loaded table into S3.".format(
                self.metastore_service.db, table_name, s3_path
            )
        )

    @logger(exclude="df")
    def load_incremental_table(
        self, df, table_name, format, partitions, schema_merging=False, **options
    ):
        """
        Loads the content of an Spark DataFrame into a table in S3 overwriting the
        corresponding partitions.

        This method will only overwrite the data of the partitions values contained in
        the Spark DataFrame. It doesn't refresh the table in the Spark Metastore,
        so you would need to do it later in the caller side if this is your desire.
        :param df: an Spark DataFrame
        :type df: SparkDataFrame
        :param table_name: the table name
        :type table_name: str
        :param format: the file format used to save
        :type format: str
        :param partitions: names of partitioning columns
        :type partitions: list
        :param schema_merging: enables the schema merging between the table in the
        Spark Metastore and the SparkDataFrame
        :type schema_merging: bool
        :param options: all other string options
        :type options: keyworded, variable-length argument list
        """
        # todo: remove the two lines below and set the conf param by the
        #  SparkClient class
        spark = BaseSparkContext.spark
        spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

        if not df:
            raise ValueError("m=load_incremental_table, msg=Spark DataFrame is empty")

        s3_path = self.metastore_service.db_path + table_name
        mod_df = (
            df.write.mode("overwrite")
            .format(format)
            .option("maxRecordsPerFile", self.MAX_RECORDS_PER_FILE)
            .partitionBy(*partitions)
        )
        for op, val in options.items():
            mod_df = mod_df.option(op, val)

        if table_name in self.metastore_service.get_table_names():
            if schema_merging:
                self.metastore_service.merge_schemas(table_name, format, partitions, df)
            logger.info(
                "m=load_incremental_table, db={}, table_name={}, msg=updating relevant "
                "partitions with the DataFrame content".format(
                    self.metastore_service.db, table_name
                )
            )
            mod_df.save(s3_path)
        else:
            logger.info(
                "m=load_incremental_table, db={}, table_name={}, msg=table does not "
                "exist in db, creating it...".format(
                    self.metastore_service.db, table_name
                )
            )
            mod_df.option("path", s3_path).saveAsTable(
                "{}.{}".format(self.metastore_service.db, table_name)
            )

        logger.info(
            "m=load_incremental_table, path={}, "
            "partitions={}, msg=loaded partitions successfully".format(
                s3_path, partitions
            )
        )
