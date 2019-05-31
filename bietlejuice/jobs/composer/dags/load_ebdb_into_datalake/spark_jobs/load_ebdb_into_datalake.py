import sys
from multiprocessing.dummy import Pool as ThreadPool

from python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import EnumDB
from bietlejuice.jobs.composer.consumers import MySQLConsumer
from bietlejuice.jobs.composer.etl.load_ebdb_into_datalake import EBDBIntoDatalakeLoader

logger = QuintoAndarLogger('load_ebdb_into_datalake')

SIZE_THRESHOLD = 1000  # size in mb to decide if a table is big
NUM_PARTITIONS = 16  # max parallel connections to use when reading a table in jdbc
BLACK_LIST = ['REVCHANGES']

AUD_DAILY_QUERY = """
  SELECT
    {table}.*
    DATE('{execution_date}') as dt
  FROM
    {table}
    JOIN UsuarioRevisionEntity on {table}.REV = UsuarioRevisionEntity.id
  WHERE
    DATE(FROM_UNIXTIME(UsuarioRevisionEntity.`timestamp`/1000)) = DATE('{execution_date}')
"""

AUD_FULL_QUERY = """
  SELECT
    {table}.*
    DATE(FROM_UNIXTIME(UsuarioRevisionEntity.`timestamp`/1000)) as dt
  FROM
    {table}
    JOIN UsuarioRevisionEntity on {table}.REV = UsuarioRevisionEntity.id
"""


def is_aud(table):
    return '_aud' in table.lower()


@logger
def full_small_table_map_function(args):
    table, loader, consumer = args
    logger.info('m=full_small_table_map_function, table={}, msg=Starting loading table.'.format(table))
    if is_aud(table):
        loader.load_full_table_into_datalake_raw(table,
                                                 consumer,
                                                 AUD_FULL_QUERY.format(table=table),
                                                 partition_by=['dt'],
                                                 read_concurrency=1)
    else:
        loader.load_full_table_into_datalake(table, consumer)
    logger.info('m=full_small_table_map_function, table={}, msg=Finished loading table.'.format(table))


@logger
def load_full_small_tables(tables, threads, loader, consumer):
    logger.info('m=load_full_small_tables, msg=Starting loading small tables...')
    tables = [(table, loader, consumer) for table in tables]
    pool = ThreadPool(threads)
    pool.map(full_small_table_map_function, tables)
    pool.close()
    pool.join()
    logger.info('m=load_full_small_tables, msg=Finished loading small tables.')


@logger
def load_full_big_tables(tables, num_partitions, loader, consumer):
    logger.info(
        'm=load_full_big_tables, msg=Starting loading big tables...')
    for table in tables:
        if is_aud(table):
            loader.load_full_table_into_datalake_raw(table,
                                                     consumer,
                                                     query=AUD_FULL_QUERY.format(table=table),
                                                     partition_by=['dt'],
                                                     read_concurrency=1)
        else:
            loader.load_full_table_into_datalake_raw(table,
                                                     consumer,
                                                     read_concurrency=num_partitions)
    logger.info(
        'm=load_full_big_tables, msg=Finished loading big tables.')


@logger
def aud_map_function(args):
    table, loader, consumer, execution_date = args
    logger.info(
        'm=aud_map_function, table={}, msg=Started loading daily updates from table'.format(table))
    loader.load_incremental_partitioned_table_into_datalake_raw(table,
                                                                consumer,
                                                                query=AUD_DAILY_QUERY.format(
                                                                    table=table,
                                                                    execution_date=execution_date),
                                                                partition_by=[('dt', execution_date)]
                                                                )
    logger.info(
        'm=aud_map_function, table={}, msg=Finished loading daily updates from table'.format(table))


@logger
def load_aud_daily(tables, threads, loader, consumer, execution_date):
    logger.info(
        'm=load_aud_daily, msg=Started loading incremental aud tables')
    tables = [(table, loader, consumer, execution_date) for table in tables]
    pool = ThreadPool(threads)
    pool.map(aud_map_function, tables)
    pool.close()
    pool.join()
    logger.info(
        'm=load_aud_daily, msg=Finished loading daily incremental aud tables')


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise RuntimeError(
            'm=__main__, msg=This script expects to receive two params: operation_mode and execution_date')
    operation_mode = sys.argv[1].lower()
    execution_date = sys.argv[2]

    mysql_consumer = MySQLConsumer(EnumDB.QuintoAndar_ebdb)

    loader = EBDBIntoDatalakeLoader()

    tables_sizes = dict(loader.get_table_names_and_sizes(mysql_consumer).collect())
    tables_sizes = {k: v for k, v in tables_sizes.items() if k not in BLACK_LIST}  # filter out blacklist

    if operation_mode == 'first_time':
        big_tables = [table[0] for table in tables_sizes.items() if
                      table[1] is not None and table[1] > SIZE_THRESHOLD]
        small_tables = [table[0] for table in tables_sizes.items() if
                        table[1] is not None and table[1] <= SIZE_THRESHOLD]

        load_full_big_tables(big_tables, NUM_PARTITIONS, loader, mysql_consumer)
        load_full_small_tables(small_tables, NUM_PARTITIONS, loader, mysql_consumer)
    elif operation_mode == 'daily':
        aud_tables = [table[0] for table in tables_sizes.items() if
                      table[1] is not None and is_aud(table[0])]
        non_aud_big_tables = [table[0] for table in tables_sizes.items() if
                              table[1] is not None and table[0] not in aud_tables and table[1] > SIZE_THRESHOLD]
        non_aud_small_tables = [table[0] for table in tables_sizes.items() if
                                table[1] is not None and table[0] not in aud_tables and table[1] <= SIZE_THRESHOLD]

        load_full_big_tables(non_aud_big_tables, NUM_PARTITIONS, loader, mysql_consumer)
        load_full_small_tables(non_aud_small_tables, NUM_PARTITIONS, loader, mysql_consumer)
        load_aud_daily(aud_tables, NUM_PARTITIONS, loader, mysql_consumer, execution_date)
    else:
        raise RuntimeError(
            'm=__main__, msg=operation_mode {} invalid, it can only be "first_time" or "daily"')
