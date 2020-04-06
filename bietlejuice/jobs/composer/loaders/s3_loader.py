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
    def load_full_table(
        self,
        df,
        database_name,
        table_name,
        format,
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
        :param format: the file format used to save
        :type format: str
        :param database_location: location of the database in the object storage
        :type database_location: str
        :param partitions: names of partitioning columns
        :type partitions: list
        :param options: all other string options
        :type options: keyworded, variable-length argument list
        :return: DataframeWriter
        """
        if not df:
            raise ValueError("m=load_full_table, msg=Spark DataFrame is empty")

        s3_path = database_location + table_name
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
            "{}.{}".format(database_name, table_name)
        )

        logger.info(
            "m=load_full_table, table={}.{}, s3_path={}, "
            "msg=loaded table into S3.".format(database_name, table_name, s3_path)
        )
        return mod_df

    @logger(exclude="df")
    def load_incremental_table(
        self,
        df,
        database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
        schema_merging=False,
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
        :param schema_merging: enables the schema merging between the table in the
        Spark Metastore and the SparkDataFrame
        :type schema_merging: bool
        :param options: all other string options
        :type options: keyworded, variable-length argument list
        :return: DataframeWriter
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
        mod_df = (
            df.write.mode("overwrite")
            .format(format_options)
            .option("maxRecordsPerFile", self.MAX_RECORDS_PER_FILE)
            .partitionBy(*partition_cols)
        )
        for op, val in options.items():
            mod_df = mod_df.option(op, val)

        if table_name in self.metastore_service.get_table_names(database_name):
            if schema_merging:
                table_schema = self.metastore_service.get_table_schema(
                    database_name, table_name
                )
                new_schema = self.metastore_service.merge_table_and_dataframe_schemas(
                    database_name, table_name, df
                )
                if new_schema != table_schema:
                    self.metastore_service.drop_table(database_name, table_name)
                    self.metastore_service.create_external_table(
                        database_name=database_name,
                        table_name=table_name,
                        table_location=s3_path,
                        table_schema=new_schema,
                        partition_cols=partition_cols,
                        format_options=format_options,
                    )
                    self.metastore_service.repair_table_partitions(
                        database_name, table_name
                    )
            logger.info(
                "m=load_incremental_table, db={}, table_name={}, msg=updating relevant "
                "partitions with the DataFrame content".format(
                    database_name, table_name
                )
            )
            mod_df.save(s3_path)
        else:
            logger.info(
                "m=load_incremental_table, db={}, table_name={}, msg=table does not "
                "exist in db, creating it...".format(database_name, table_name)
            )
            mod_df.option("path", s3_path).saveAsTable(
                "{}.{}".format(database_name, table_name)
            )

        logger.info(
            "m=load_incremental_table, path={}, "
            "partitions={}, msg=loaded partitions successfully".format(
                s3_path, partition_cols
            )
        )

        return mod_df
