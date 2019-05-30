import sys
import os
from multiprocessing.dummy import Pool as ThreadPool
sys.path.append(os.path.dirname(os.path.expanduser('~/bi-etl-ejuice/bietlejuice/jobs/composer/etl/load_data_into_datalake_etl.py')))
sys.path.append(os.path.dirname(os.path.expanduser('~/bi-etl-ejuice/bietlejuice/jobs/composer/consumers/my_sql_consumer.py')))

from load_data_into_datalake_etl import LoadDataIntoDatalakeETL
from my_sql_consumer import MySQLConsumer
from python_logger import QuintoAndarLogger
logger = QuintoAndarLogger()

op = 'full'  # full or daily
size_threshold = 1000  # size in mb to decide if a table is big
num_partitions = 16  # how much parallel connections to use when reading a table in jdbc
black_list = ['REVCHANGES']

aud_daily_query = """
  SELECT
    {table}.*
    DATE(NOW() - INTERVAL 1 DAY) as dt
  FROM
    {table}
    JOIN UsuarioRevisionEntity on {table}.REV = UsuarioRevisionEntity.id
  WHERE
    DATE(FROM_UNIXTIME(UsuarioRevisionEntity.`timestamp`/1000)) = DATE(NOW() - INTERVAL 1 DAY)
"""

aud_full_query = """
  (SELECT
    {table}.*
    DATE(FROM_UNIXTIME(UsuarioRevisionEntity.`timestamp`/1000)) as dt
  FROM
    {table}
    JOIN UsuarioRevisionEntity on {table}.REV = UsuarioRevisionEntity.id) as {table}
"""


def is_aud(table):
    return '_aud' in table.lower()


@logger
def small_table_map_function(args):
    table, loader, consumer = args
    logger.info('m=small_table_map_function, msg=Start pulling table {}'.format(table))
    if is_aud(table):
        loader.load_full_table_into_datalake(table, consumer, aud_full_query.format(table=table), partition_by='dt', concurrency=1)
    else:
        loader.load_full_table_into_datalake(table, consumer)
    logger.info('m=small_table_map_function, msg=Finished pulling table {}'.format(table))


@logger
def copy_small_tables(tables, threads, loader, consumer):
    logger.info('m=copy_small_tables, msg=Started pulling small tables')
    tables = [(table, loader, consumer) for table in tables]
    pool = ThreadPool(threads)
    pool.map(small_table_map_function, tables)
    pool.close()
    pool.join()
    logger.info('m=copy_small_tables, msg=Finished pulling small tables')


@logger
def copy_big_tables(tables, num_partitions, loader, consumer):
    logger.info(
        'm=copy_big_tables, msg=Started pulling big tables')
    for table in tables:
        if is_aud(table):
            loader.load_full_table_into_datalake(table, consumer, aud_full_query.format(table=table), partition_by='dt', concurrency=1)
        else:
            loader.load_full_table_into_datalake(table, consumer, concurrency=num_partitions)
    logger.info(
        'm=copy_big_tables, msg=Finished pulling big tables')


@logger
def aud_map_function(args):
    table, loader, consumer = args
    logger.info(
        'm=aud_map_function, msg=Started pulling daily updates of - {}'.format(table))
    loader.load_incremental_partitioned_table_into_datalake(table, aud_daily_query.format(table=table), consumer, partition_by='dt')
    logger.info(
        'm=aud_map_function, msg=Finished pulling daily updates of - {}'.format(table))


@logger
def copy_aud_daily(tables, threads, loader, consumer):
    logger.info(
        'm=copy_aud_daily, msg=Started pulling daily incremental aud tables')
    tables = [(table, loader, consumer) for table in tables]
    pool = ThreadPool(threads)
    results = pool.map(aud_map_function, tables)
    pool.close()
    pool.join()
    logger.info(
        'm=copy_aud_daily, msg=Finished pulling daily incremental aud tables')


def main():
    host = 'quintoandardbprod-read1.ciuoqxapzjot.us-east-1.rds.amazonaws.com'
    port = '3306'
    database = 'ebdb'
    username = "bi"
    password = "paraguay-attorney-dignity"

    consumer = MySQLConsumer(host,
                             port,
                             database,
                             username,
                             password)

    loader = LoadDataIntoDatalakeETL()

    tables_sizes = dict(loader.get_table_names_and_sizes_from_source(consumer).collect())
    tables_sizes = {k: v for k, v in tables_sizes.items() if k not in black_list}  # filter out blacklist

    if op == 'full':
        big_tables = [table[0] for table in tables_sizes.items() if
                      table[1] is not None and table[1] > size_threshold]
        small_tables = [table[0] for table in tables_sizes.items() if
                        table[1] is not None and table[1] <= size_threshold]

        copy_big_tables(big_tables, num_partitions, loader, consumer)
        copy_small_tables(small_tables, num_partitions, loader, consumer)

    if op == 'daily':
        aud_tables = [table[0] for table in tables_sizes.items() if
                      table[1] is not None and table[0][-3:] == 'AUD']
        non_aud_big_tables = [table[0] for table in tables_sizes.items() if
                              table[1] is not None and table[0] not in aud_tables and table[1] > size_threshold]
        non_aud_small_tables = [table[0] for table in tables_sizes.items() if
                                table[1] is not None and table[0] not in aud_tables and table[1] <= size_threshold]

        copy_big_tables(non_aud_big_tables, num_partitions, loader, consumer)
        copy_small_tables(non_aud_small_tables, num_partitions, loader, consumer)
        copy_aud_daily(aud_tables, num_partitions, loader, consumer)


if __name__ == '__main__':
    main()
