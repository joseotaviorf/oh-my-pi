from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("DataframeIntoDatalakeLoader")

spark = BaseSparkContext.spark
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")


class DataframeIntoDatalakeLoader:
    def __init__(self, format, metastore_service):
        self.format = format
        self.metastore_service = metastore_service

    def _save_as_table_write_df(self, write_df, table_name):
        write_df.option(
            "path", self.metastore_service.db_path + table_name
        ).saveAsTable("{}.{}".format(self.metastore_service.db, table_name))

    def _save_write_df(self, write_df, table_name):
        write_df.save(self.metastore_service.db_path + table_name)

    @logger(exclude="df")
    def partition_overwrite_load(
        self, df, partition_by_list, table_name, schema_merging
    ):
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
            self._save_as_table_write_df(write_df, table_name)
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
            self._save_write_df(write_df, table_name)
        logger.info(
            "m=partition_overwrite_load, write finished, new data in: s3 path={} partitions={}".format(
                self.metastore_service.db_path + table_name, str(partition_by_list)
            )
        )
