from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import BaseSparkContext
spark, sqlContext = BaseSparkContext.spark, BaseSparkContext.sqlContext


logger = QuintoAndarLogger('DataFrameService')


class DataFrameService():

    @staticmethod
    @logger
    def incremental_write(df, file_format, partition_by_list, db, table_name, path):
        write_df = df.write \
            .mode('overwrite') \
            .format(file_format) \
            .partitionBy(*partition_by_list)

        if table_name not in sqlContext.tableNames(dbName=db):
            logger.info('m=incremental_write, db={}, table_name={}, '
                        .format(db, table_name) + 'msg=table does not exist in db, creating new...')
            write_df.option('path', path) \
                .saveAsTable(db + '.' + table_name)
        else:
            logger.info('m=incremental_write, db={}, table_name={}, '
                        .format(db, table_name) + 'insert overwrite on right partition')
            write_df.save(path)
            spark.sql('msck repair table {}.{}'.format(db, table_name))

        logger.info('m=incremental_write, write finished, new data in: s3 path={} partitions={}'
                    .format(path, str(partition_by_list)))
