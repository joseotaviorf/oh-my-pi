import time
from collections import OrderedDict

import boto3
from pyspark.sql import SparkSession
from python_logger import QuintoAndarLogger

logger = QuintoAndarLogger('EBDBIntoDatalakeLoader')

QUERY_OUT_PATH = 's3://5a-datalake/temp/databricks_output/'


class EBDBIntoDatalakeLoader:
    RAW_PATH = 's3://5a-datalake/temp/ebdb'
    ATHENA_RAW_SCHEMA = 'datalake_test'
    RAW_FORMAT = 'json'
    DROP_QUERY_TEMPLATE = "DROP TABLE IF EXISTS `{database}`.`{table_name}`;"
    CREATE_QUERY_TEMPLATE = """CREATE EXTERNAL TABLE IF NOT EXISTS
                            `{database}`.`{table_name}`
                            (
                              {columns}
                            )
                            {partitioned_by}
                            {format}
                            LOCATION '{path}'
                            ;"""
    CREATE_QUERY_RAW_FORMAT = 'ROW FORMAT serde org.apache.hive.hcatalog.data.JsonSerDe'

    @logger
    def load_full_table_into_datalake_raw(self, table, consumer, query=None, partition_by=None, read_concurrency=1):
        db = consumer.connection['db']
        final_path = '{}/{}'.format(self.RAW_PATH, table.lower())

        logger.info('m=load_full_table_into_datalake_raw, msg=Getting {}.{} data...'.format(db, table))
        if query:
            df = consumer.get_data_from_query(query)
        else:
            if read_concurrency > 1:
                df = consumer.get_data_from_table_in_parallel(table, read_concurrency)
            else:
                df = consumer.get_data_from_table(table)

        logger.info(
            'm=load_full_table_into_datalake_raw, msg=Writing {}.{} data into datalake...'.format(db,
                                                                                                  table))
        # create the db in spark metastore in case it doesn't exist it
        SparkSession.builder.getOrCreate().sql('CREATE DATABASE IF NOT EXISTS {}'.format(db))
        write_df = df.write.mode("overwrite").format(self.RAW_FORMAT).option('path', final_path)
        if partition_by:
            for col in partition_by:
                write_df = write_df.partitionBy(col)
        write_df.saveAsTable(db + '.' + table)
        logger.info(
            'm=load_full_table_into_datalake_raw, msg=Copied table {}.{} into datalake ({}).'.format(db,
                                                                                                     table,
                                                                                                     final_path))

    @logger
    def load_incremental_partitioned_table_into_datalake_raw(self, table, consumer, query, partition_by):
        if not partition_by:
            raise RuntimeError(
                'm=load_incremental_partitioned_table_into_datalake_raw, msg=partition_by param is'
                'required to not overwrite the entire table but a single partition')
        db = consumer.connection['db']
        final_path = self.RAW_PATH + table.lower()
        for key, val in partition_by:
            final_path += '/{}={}'.format(key, val)

        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, query={},'
            'msg=Getting data from query...'.format(query))
        df = consumer.get_data_from_query(query)
        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, msg=Writing data into datalake...')
        df.write.mode("overwrite").format(self.RAW_FORMAT).save(final_path)

        # refresh table in spark metastore
        spark = SparkSession.builder.getOrCreate()
        spark.sql('REFRESH TABLE {}.{}'.format(db, table))
        spark.sql('MSCK REPAIR TABLE {}.{}'.format(db, table))
        logger.info(
            'm=load_incremental_partitioned_table_into_datalake_raw, msg=Loaded successfully incremental'
            'table data {}.{} into datalake ({}).'.format(db, table, final_path))

    @logger
    def get_table_names_and_sizes_from_consumer(self, consumer):
        return consumer.get_table_names_and_sizes()

    @logger
    def is_db_empty(self, consumer):
        return consumer.is_db_emtpy()

    @logger
    def create_athena_external_table(self, consumer, table, partition_by=None):
        athena_schema = self.ATHENA_RAW_SCHEMA
        file_format = self.CREATE_QUERY_RAW_FORMAT

        table_schema = consumer.get_table_schema(table).collect()
        table_schema = OrderedDict(
            [(col_name, col_type.lower.replace('timestamp', 'string')) for col_name, col_type in table_schema.items()])

        drop_query = self.DROP_QUERY_TEMPLATE.format(database=athena_schema,
                                                     table=table)
        execute_athena_query(get_athena_client(), drop_query, athena_schema)
        logger.info('m=create_athena_external_table, msg=Dropped table {}.{} in Athena successfully'.format(
            athena_schema,
            table))
        columns_section = ',\n  '.join(['`' + col + '` ' + col_type.upper() for col, col_type in table_schema.items()])
        partitions_section = ''
        if partition_by:
            partitions_section = 'PARTITIONED BY (\n  {}\n)'.format(
                ',\n  '.join(['`' + col + '` ' + table_schema[col] for col in partition_by]))
        create_query = self.CREATE_QUERY_TEMPLATE.format(database=athena_schema,
                                                         table=table,
                                                         columns=columns_section,
                                                         partitioned_by=partitions_section,
                                                         format=file_format,
                                                         path='{}/{}'.format(self.RAW_PATH, table)
                                                         )
        execute_athena_query(get_athena_client(), create_query, athena_schema)
        execute_athena_query(get_athena_client, 'MSCK REPAIR TABLE {}.{};'.format(athena_schema, table))

        logger.info('m=_create_athena_external_table, msg=The table {}.{} was created successfully in Athena'.format(
            athena_schema, table))


@logger
def get_athena_client():
    return boto3.client('athena', 'us-east-1')


@logger
def start_athena_query(client, query, database):
    response = client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={
            'Database': database
        },
        ResultConfiguration={
            'OutputLocation': QUERY_OUT_PATH,
        }
    )
    return response


@logger
def execute_athena_query(client, query, database):
    execution = start_athena_query(client, query, database)
    execution_id = execution['QueryExecutionId']
    state = 'RUNNING'
    while state in ['RUNNING']:
        response = client.get_query_execution(QueryExecutionId=execution_id)
        if 'QueryExecution' in response and \
                'Status' in response['QueryExecution'] and \
                'State' in response['QueryExecution']['Status']:
            state = response['QueryExecution']['Status']['State']
            if state == 'FAILED':
                raise RuntimeError(
                    'm=execute_athena_query, msg=Athena client failed when executing the query., query={}'.format(
                        query))
            elif state == 'SUCCEEDED':
                return
        time.sleep(3)
