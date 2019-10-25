from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("SparkDataframeIntoDatalakeLoader")

spark = BaseSparkContext.spark
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


class SparkDataframeIntoDatalakeLoader:
    MAX_RECORDS_PER_FILE = 250000

    def __init__(self, format, metastore_service):
        self.format = format
        self.metastore_service = metastore_service

    def _save_df_as_table(self, df, table_name):
        """
        :param df: dataframe ready to write with the options mode, format partitionBy (if exists) already set
        :param table_name: name of the table in the schema (without schema prefix)
        :return: None
        """
        df.option("path", self.metastore_service.db_path + table_name).saveAsTable(
            "{}.{}".format(self.metastore_service.db, table_name)
        )

    def _save_df(self, df, table_name):
        """
        :param df: dataframe ready to write, with the options mode, format partitionBy (if exists) already set
        :param table_name: name of the folder in the db path where is the table data
        :return: None
        """
        df.save(self.metastore_service.db_path + table_name)

    def _apply_default_overwrite_options(self, df):
        return (
            df.write.mode("overwrite")
            .format(self.format)
            .option("maxRecordsPerFile", self.MAX_RECORDS_PER_FILE)
        )

    @logger(exclude="df")
    def overwrite_partition(self, df, partition_by_list, table_name, schema_merging):
        """
        Load the data into datalake in overwrite mode but with dynamic partition enable.
        The new data will only overwrite the partitions values contained in the df.

        :param df: spark dataframe with the data to load
        :param partition_by_list: list of the column names which the table is partitioned
        :param table_name: name of the table in the schema (without schema prefix)
        :param schema_merging: boolean field to enable the schema merging between the table in the spark metastore and the df
        :return: None
        """
        if not df:
            raise ValueError("m=overwrite_partition, msg=input df is None")

        write_df = self._apply_default_overwrite_options(df).partitionBy(
            *partition_by_list
        )

        self.metastore_service.create_database()  # if not exists
        if table_name not in self.metastore_service.get_table_names():
            logger.info(
                "m=overwrite_partition, db={}, table_name={}, ".format(
                    self.metastore_service.db, table_name
                )
                + "msg=table does not exist in db, creating new..."
            )
            self._save_df_as_table(write_df, table_name)
        else:
            if schema_merging:
                self.metastore_service.merge_schemas(
                    table_name, self.format, partition_by_list, df
                )
            logger.info(
                "m=overwrite_partition, db={}, table_name={}, ".format(
                    self.metastore_service.db, table_name
                )
                + "insert overwrite on right partition"
            )
            self._save_df(write_df, table_name)
        logger.info(
            "m=overwrite_partition, write finished, new data in: s3 path={} partitions={}".format(
                self.metastore_service.db_path + table_name, str(partition_by_list)
            )
        )
        # after rewriting an existing partition, we must refresh the table
        self.metastore_service.refresh_table(table_name)

    @logger(exclude="df")
    def overwrite_table(self, df, table_name):
        """
        Load the data into datalake in overwrite mode.
        This mode will replace the definition of the table completely. This method don't expected the df to be
        partitioned, if you want to save as a table with partitions use the overwrite_partition method instead.

        :param df: spark dataframe with the data to load
        :param table_name: name of the table in the schema (without schema prefix)
        :return: None
        """
        if not df:
            raise ValueError("m=overwrite_partition, msg=input df is None")
        self.metastore_service.create_database()  # if not exists

        self.metastore_service.drop_table(table_name)
        write_df = self._apply_default_overwrite_options(df)
        self._save_df_as_table(write_df, table_name)

        logger.info(
            "m=overwrite, {}.{} table created at s3 path={}".format(
                self.metastore_service.db,
                table_name,
                self.metastore_service.db_path + table_name,
            )
        )
