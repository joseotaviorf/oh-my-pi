from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.spark import BaseSparkContext

logger = QuintoAndarLogger("DataframeIntoDatalakeLoader")

spark= BaseSparkContext.spark
spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

class DataframeIntoDatalakeLoader:
    def __ini__(self, db, format, metastore_service):
        self.db = db
        self.format = format
        self.metastore_service = metastore_service

    def _save_as_table_write_df(self, write_df, path, name):
        write_df.option("path", path).saveAsTable(name)

    def _save_write_df(self, write_df, path):
        write_df.save(path)

    @logger(exclude="df")
    def partition_overwrite_load(
            self, df, partition_by_list, table_name, path, schema_merging
    ):
        if not df:
            raise ValueError("m=partition_overwrite_load, msg=input df is None")
        write_df = (
            df.write.mode("overwrite")
                .format(self.format)
                .partitionBy(*partition_by_list)
        )
        if table_name not in self.metastore_service.get_table_names():
            logger.info(
                "m=partition_overwrite_load, db={}, table_name={}, ".format(self.db, table_name)
                + "msg=table does not exist in db, creating new..."
            )
            self._save_as_table_write_df(write_df, path, "{}.{}".format(self.db, table_name))
            # write_df.option("path", path).saveAsTable(db + "." + table_name)
        else:
            if schema_merging:
                self.metastore_service.make_schema_merging(
                    table_name, self.db, self.format, path, partition_by_list, df
                )
            logger.info(
                "m=partition_overwrite_load, db={}, table_name={}, ".format(self.db, table_name)
                + "insert overwrite on right partition"
            )
            self._save_write_df(write_df, path)
            # write_df.save(path)
        logger.info(
            "m=partition_overwrite_load, write finished, new data in: s3 path={} partitions={}".format(
                path, str(partition_by_list)
            )
        )
