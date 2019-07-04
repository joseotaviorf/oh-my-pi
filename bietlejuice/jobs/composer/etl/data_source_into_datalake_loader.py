from collections import OrderedDict

from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.wrappers import AthenaClient

logger = QuintoAndarLogger('DataSourceIntoDataLakeLoader')


class DataSourceIntoDataLakeLoader:
    RAW_FORMAT = 'json'
    RAW_CODEC = 'gzip'
    DATALAKE_RAW_DB = 'datalake_raw_spark'
    DATALAKE_RAW_PATH = 's3://5a-datalake/raw_spark'
    DROP_QUERY_TEMPLATE = "DROP TABLE IF EXISTS `{database}`.`{table}`;"
    CREATE_QUERY_TEMPLATE = """CREATE EXTERNAL TABLE IF NOT EXISTS
                            `{database}`.`{table}`
                            (
                              {columns}
                            )
                            {partitioned_by}
                            {format}
                            LOCATION '{path}'
                            ;"""
    CREATE_QUERY_RAW_FORMAT = "ROW FORMAT serde 'org.apache.hive.hcatalog.data.JsonSerDe'"

    @staticmethod
    @logger
    def load_full_table_into_datalake_raw(table_name, consumer, query=None, partition_by=None, concurrency=1):
        db_source = consumer.connection['db']
        final_path = '{}/{}/{}'.format(
            DataSourceIntoDataLakeLoader.DATALAKE_RAW_PATH,
            db_source,
            table_name.lower()
        )

        logger.info('m=load_full_table_into_datalake_raw, table={}.{}, msg=Getting  data...'.format(
            db_source, table_name))
        if query:
            df = consumer.get_data_from_query(query)
        else:
            if concurrency > 1:
                df = consumer.get_data_from_table_in_parallel(table_name, concurrency)
            else:
                df = consumer.get_data_from_table(table_name)

        logger.info(
            'm=load_full_table_into_datalake_raw, table={}.{},'
            'msg=Writing data into datalake...'.format(db_source,
                                                       table_name))
        # create the db in spark metastore in case it doesn't exist it
        SparkSession.builder.getOrCreate().sql(
            'CREATE DATABASE IF NOT EXISTS {}'.format(DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB))
        write_df = df.write.mode("overwrite") \
            .option("compression", DataSourceIntoDataLakeLoader.RAW_CODEC) \
            .format(DataSourceIntoDataLakeLoader.RAW_FORMAT) \
            .option('path', final_path)
        if partition_by:
            for col in partition_by:
                write_df = write_df.partitionBy(col)
        new_table_name = '{}_{}'.format(db_source, table_name)
        write_df.saveAsTable('{}.{}'.format(
            DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
            new_table_name
        ))
        logger.info(
            'm=load_full_table_into_datalake_raw, table={}.{},'
            'msg=Copied table into datalake ({}).'.format(
                DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
                new_table_name,
                final_path
            )
        )

    @staticmethod
    @logger
    def load_incremental_partitioned_table_into_datalake_raw(table_name, consumer, query,
                                                             partition_by):
        if not partition_by:
            raise RuntimeError(
                'm=load_incremental_partitioned_table_into_datalake_raw,'
                'msg=partition_by param is required to not overwrite the'
                'entire table but a single partition')
        data_source = consumer.connection['db']
        final_path = '{}/{}/{}'.format(
            DataSourceIntoDataLakeLoader.DATALAKE_RAW_PATH,
            data_source,
            table_name.lower()
        )
        for key, val in partition_by:
            final_path += '/{}={}'.format(key, val)

        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, query={},'
            'msg=Getting data from query...'.format(query))
        df = consumer.get_data_from_query(query)
        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, msg=Writing data into datalake...')
        df.write.mode("overwrite") \
            .option("compression", DataSourceIntoDataLakeLoader.RAW_CODEC) \
            .format(DataSourceIntoDataLakeLoader.RAW_FORMAT) \
            .save(final_path)

        # refresh table in spark metastore
        spark = SparkSession.builder.getOrCreate()
        new_table_name = '{}_{}'.format(data_source, table_name)
        spark.sql('REFRESH TABLE {}.{}'.format(
            DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
            new_table_name
        ))
        spark.sql('MSCK REPAIR TABLE {}.{}'.format(
            DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
            new_table_name
        ))
        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, table={}.{},'
            'msg=Loaded successfully incremental data into datalake ({}).'.format(
                DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
                new_table_name,
                final_path
            )
        )

    @staticmethod
    @logger
    def get_table_names_and_sizes(consumer):
        return consumer.get_table_names_and_sizes()

    @staticmethod
    @logger
    def is_db_empty(consumer):
        return consumer.is_db_emtpy()

    @staticmethod
    @logger
    def create_athena_external_table(consumer, table_name, db_source, partition_by=None):
        if not table_name.startswith(db_source + '_'):
            raise RuntimeError('m=create_athena_external_table, table_name={}, db_source={}, '
                               'msg=Database source must be the prefix of the '
                               'table_name'.format(table_name, db_source)
                               )

        drop_query = DataSourceIntoDataLakeLoader.DROP_QUERY_TEMPLATE.format(
            database=DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
            table=table_name
        )
        AthenaClient.execute_athena_query(
            drop_query,
            DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB
        )
        logger.info('m=create_athena_external_table, table={}.{}, msg=Dropped '
                    'table in Athena successfully'.format(DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
                                                          table_name)
                    )

        table_schema = consumer.get_table_schema(table_name).collect()
        table_schema = OrderedDict(
            [(row['col_name'], row['col_type'].lower().replace('timestamp', 'string')) for row in table_schema])

        columns_section = ',\n  '.join(
            ['`' + col + '` ' + col_type.upper() for col, col_type in table_schema.items() if
             not partition_by or col not in partition_by])
        partitions_section = ''
        if partition_by:
            partitions_section = 'PARTITIONED BY (\n  {}\n)'.format(
                ',\n  '.join(['`' + col + '` ' + table_schema[col] for col in partition_by]))
        create_query = DataSourceIntoDataLakeLoader.CREATE_QUERY_TEMPLATE.format(
            database=DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
            table=table_name,
            columns=columns_section,
            partitioned_by=partitions_section,
            format=DataSourceIntoDataLakeLoader.CREATE_QUERY_RAW_FORMAT,
            path='{}/{}/{}'.format(
                DataSourceIntoDataLakeLoader.DATALAKE_RAW_PATH,
                db_source,
                table_name[len(db_source) + 1:]
            )
        )
        AthenaClient.execute_athena_query(create_query, DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB)
        if partition_by:
            AthenaClient.execute_athena_query(
                'MSCK REPAIR TABLE `{}`.`{}`;'.format(
                    DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB,
                    table_name
                ), DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB
            )

        logger.info(
            'm=_create_athena_external_table, table={}.{}, msg=The table was created successfully '
            'in Athena'.format(
                DataSourceIntoDataLakeLoader.DATALAKE_RAW_DB, table_name))
