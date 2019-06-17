from collections import OrderedDict

from pyspark.sql import SparkSession
from python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.wrappers import AthenaClient

logger = QuintoAndarLogger('DocxIntoDatalakeLoader')


class DocxIntoDatalakeLoader:
    RAW_PATH = 's3://5a-datalake/temp/docx'
    ATHENA_RAW_SCHEMA = 'docx'
    RAW_FORMAT = 'json'
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
    def load_full_table_into_datalake_raw(table, consumer, query=None, partition_by=None, concurrency=1):
        db = consumer.connection['db']
        final_path = '{}/{}'.format(DocxIntoDatalakeLoader.RAW_PATH, table.lower())

        logger.info('m=load_full_table_into_datalake_raw, table={}.{}, msg=Getting  data...'.format(db, table))
        if query:
            df = consumer.get_data_from_query(query)
        else:
            if concurrency > 1:
                df = consumer.get_data_from_table_in_parallel(table, concurrency)
            else:
                df = consumer.get_data_from_table(table)

        logger.info(
            'm=load_full_table_into_datalake_raw, table={}.{},'
            'msg=Writing data into datalake...'.format(db,
                                                       table))
        # create the db in spark metastore in case it doesn't exist it
        SparkSession.builder.getOrCreate().sql('CREATE DATABASE IF NOT EXISTS {}'.format(db))
        write_df = df.write.mode("overwrite") \
            .option("compression", "gzip") \
            .format(DocxIntoDatalakeLoader.RAW_FORMAT) \
            .option('path', final_path)
        if partition_by:
            for col in partition_by:
                write_df = write_df.partitionBy(col)
        write_df.saveAsTable(db + '.' + table)
        logger.info(
            'm=load_full_table_into_datalake_raw, table={}.{},'
            'msg=Copied table into datalake ({}).'.format(db,
                                                          table,
                                                          final_path))

    @staticmethod
    @logger
    def load_incremental_partitioned_table_into_datalake_raw(table, consumer, query,
                                                             partition_by):
        if not partition_by:
            raise RuntimeError(
                'm=load_incremental_partitioned_table_into_datalake_raw,'
                'msg=partition_by param is required to not overwrite the'
                'entire table but a single partition')
        db = consumer.connection['db']
        final_path = DocxIntoDatalakeLoader.RAW_PATH + table.lower()
        for key, val in partition_by:
            final_path += '/{}={}'.format(key, val)

        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, query={},'
            'msg=Getting data from query...'.format(query))
        df = consumer.get_data_from_query(query)
        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, msg=Writing data into datalake...')
        df.write.mode("overwrite") \
            .option("compression", "gzip") \
            .format(DocxIntoDatalakeLoader.RAW_FORMAT) \
            .save(final_path)

        # refresh table in spark metastore
        spark = SparkSession.builder.getOrCreate()
        spark.sql('REFRESH TABLE {}.{}'.format(db, table))
        spark.sql('MSCK REPAIR TABLE {}.{}'.format(db, table))
        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, table={}.{},'
            'msg=Loaded successfully incremental data into datalake ({}).'.format(db, table, final_path))

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
    def create_athena_external_table(consumer, table, partition_by=None):
        file_format = DocxIntoDatalakeLoader.CREATE_QUERY_RAW_FORMAT

        drop_query = DocxIntoDatalakeLoader.DROP_QUERY_TEMPLATE.format(
            database=DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA,
            table=table)
        AthenaClient.execute_athena_query(drop_query, DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA)
        logger.info('m=create_athena_external_table, table={}.{}, msg=Dropped table in Athena successfully'.format(
            DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA,
            table))

        table_schema = consumer.get_table_schema(table).collect()
        table_schema = OrderedDict(
            [(row['col_name'], row['data_type'].lower().replace('timestamp', 'string')) for row in table_schema])

        columns_section = ',\n  '.join(
            ['`' + col + '` ' + col_type.upper() for col, col_type in table_schema.items() if
             not partition_by or col not in partition_by])
        partitions_section = ''
        if partition_by:
            partitions_section = 'PARTITIONED BY (\n  {}\n)'.format(
                ',\n  '.join(['`' + col + '` ' + table_schema[col] for col in partition_by]))
        create_query = DocxIntoDatalakeLoader.CREATE_QUERY_TEMPLATE.format(
            database=DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA,
            table=table,
            columns=columns_section,
            partitioned_by=partitions_section,
            format=file_format,
            path='{}/{}'.format(
                DocxIntoDatalakeLoader.RAW_PATH, table)
        )
        AthenaClient.execute_athena_query(create_query, DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA)
        if partition_by:
            AthenaClient.execute_athena_query(
                'MSCK REPAIR TABLE `{}`.`{}`;'.format(DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA,
                                                      table),
                DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA)

        logger.info(
            'm=_create_athena_external_table, table={}.{}, msg=The table was created successfully in Athena'.format(
                DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA, table))
