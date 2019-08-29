from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("DataframeIntoDatalakeLoader")

spark = BaseSparkContext.spark
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


class SparkDataframeIntoDatalakeLoader:
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

    @logger(exclude="df")
    def overwrite_partition(self, df, partition_by_list, table_name, schema_merging):
        """
        Load the data into datalake in overwrite mode but with dynamic partition enable. That means that the new data will only overwrite the partitions values contained in the df

        :param df: spark dataframe with the data to load
        :param partition_by_list: list of the column names which the table is partitioned
        :param table_name: names of the table in the schema (without schema prefix)
        :param schema_merging: boolean field to enable the schema merging between the table in the spark metastore and the df
        :return: None
        """
        if not df:
            raise ValueError("m=partition_overwrite_load, msg=input df is None")

        write_df = (
            df.write.mode("overwrite")
            .format(self.format)
            .partitionBy(*partition_by_list)
        )

        self.metastore_service.create_database()  # if not exists
        if table_name not in self.metastore_service.get_table_names():
            logger.info(
                "m=partition_overwrite_load, db={}, table_name={}, ".format(
                    self.metastore_service.db, table_name
                )
                + "msg=table does not exist in db, creating new..."
            )
            self._save_df_as_table(write_df, table_name)
        else:
            if schema_merging:
                self.metastore_service.make_schema_merging(
                    table_name, self.format, partition_by_list, df
                )
            logger.info(
                "m=partition_overwrite_load, db={}, table_name={}, ".format(
                    self.metastore_service.db, table_name
                )
                + "insert overwrite on right partition"
            )
            self._save_df(write_df, table_name)
        logger.info(
            "m=partition_overwrite_load, write finished, new data in: s3 path={} partitions={}".format(
                self.metastore_service.db_path + table_name, str(partition_by_list)
            )
        )
