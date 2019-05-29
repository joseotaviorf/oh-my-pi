import datetime
from multiprocessing.dummy import Pool as ThreadPool

import spark as spark
from django import db
from python_logger import QuintoAndarLogger

op = 'full'  # full, daily, pre_daily
black_list = ['REVCHANGES']
write_format = 'json'
path = 's3://5a-datalake/temp/ebdb/'

logger = QuintoAndarLogger()


@logger
def copy_full_table(table, consumer):
    db = consumer.connection['db']
    logger.info('m=copy_full_table, msg=Start pulling table {}.{}.'.format(db, table))
    df = consumer.get_data_from_table(table)
    try:
        df.write.mode("overwrite").format(write_format).option('path', path + table.lower()).saveAsTable(
            db + '.' + table)
    except Exception as e:
        raise RuntimeError('m=copy_full_table, msg=Cannot copy table to datalake {}.{}, e={}'.format(db, table, e))

    logger.info('m=copy_full_table, msg=Finished pulling table {}.{}.'.format(db, table))


@logger
def copy_incremental_table(table, consumer):
    db = consumer.connection['db']
    logger.info('m=copy_incremental_table, msg=Start pulling table {}.{}.'.format(db, table))
    df = consumer.get_data_from_table(table)
    df.write.mode("append").format(write_format).option('path', path + table.lower()).saveAsTable(
        db + '.' + table)
    logger.info('m=copy_full_table, msg=Finished pulling table {}.{}.'.format(db, table))


@logger
def copy_small_tables(tables, threads_nb, consumer):
    db = consumer.connection['db']
    logger.info('m=copy_small_tables, msg=Started pulling small tables {}.{}.'.format(db, tables))
    tables = [(table, consumer) for table in tables]
    pool = ThreadPool(threads_nb)
    pool.map(lambda table: copy_full_table(table[0], table[1]), tables)
    pool.close()
    pool.join()
    logger.info('m=copy_small_tables, msg=Finished pulling small tables {}.{}.'.format(db, tables))


@logger
def copy_big_table(table, num_partitions, consumer):
    db = consumer.connection['db']
    partition_column = consumer._get_partition_column_from_table(table)
    if partition_column:
        logger.info(
            'm=copy_big_table, msg=Started pulling table {}.{} with partition column {}.'.format(db, table,
                                                                                                 partition_column))
        df = consumer.get_data_from_table_in_parallel(table, partition_column, num_partitions)
    else:
        logger.info(
            'm=copy_big_table, msg=Could not get partition column in {}.{}, Started pulling it with a single query.'.format(
                db, table))
        df = consumer.get_data_from_table(table)
    try:
        df.write.mode("overwrite").format(write_format).option('path', path + table.lower()).saveAsTable(
            db + '.' + table)
    except Exception as e:
        raise RuntimeError('m=copy_big_table, msg=Cannot copy table to datalake {}.{}, e={}'.format(db, table, e))

    logger.info('m=copy_big_table, msg=Finished pulling table {}.{}.'.format(db, table))


@logger
def copy_big_tables(tables, num_partitions, consumer):
    db = consumer.connection['db']
    logger.info(
        'm=copy_big_tables, msg=Started pulling tables {}.{}'.format(db, tables))
    for table in tables:
        copy_big_table(table, num_partitions, consumer)


@logger
def aud_map_function(table_consumer_tuple):
    table, consumer = table_consumer_tuple
    query = """
  SELECT
    {table}.*

  FROM
    {table}
    JOIN UsuarioRevisionEntity on {table}.REV = UsuarioRevisionEntity.id
  WHERE
    DATE(FROM_UNIXTIME(UsuarioRevisionEntity.`timestamp`/1000)) = DATE(NOW() - INTERVAL 1 DAY)
  """
    print(str(datetime.datetime.now()) + " Start pulling query - " + table)
    df = consumer.get_data_from_query(query.format(table=table))
    df.write.mode("append").format(write_format).option('path', path + table.lower()).saveAsTable(
        consumer.connection['db'] + '.' + table)
    print(str(datetime.datetime.now()) + " Finished pulling " + consumer.connection['db'] + '.' + table)


@logger
def aud_pre_daily_map_function(table_consumer_tuple):
    table, consumer = table_consumer_tuple
    query = """
  SELECT
    {table}.*
  FROM
    {table}
    JOIN UsuarioRevisionEntity on {table}.REV = UsuarioRevisionEntity.id
  WHERE
    DATE(FROM_UNIXTIME(UsuarioRevisionEntity.`timestamp`/1000)) < DATE(NOW())
  """
    print(str(datetime.datetime.now()) + " Start pulling query - " + table)
    df = consumer.get_data_from_query(query.format(table=table))
    try:
        df.write.mode("overwrite").format(write_format).option('path', path + table.lower()).saveAsTable(
            consumer.connection['db'] + '.' + table)
    except:
        print(datetime.datetime.now() + ' ' + table + ' Overwrite error -> clean table and recreate')
        spark.sql('drop table {}.{}'.format(db, table))
        dbutils.fs.rm(path + table.lower(), True)
        df.write.mode("overwrite").format(write_format).option('path', path + table.lower()).saveAsTable(
            consumer.connection['db'] + '.' + table)
    print(str(datetime.datetime.now()) + " Finished pulling " + consumer.connection['db'] + '.' + table)


def aud_strategy(tables, threads, consumer, pre_daily=False):
    print(str(datetime.datetime.now()) + " AUD tables strategy started")
    table_consumer_tuples = [(table, consumer) for table in tables]
    pool = ThreadPool(threads)
    if pre_daily:
        results = pool.map(aud_pre_daily_map_function, table_consumer_tuples)
    else:
        results = pool.map(aud_map_function, table_consumer_tuples)
    pool.close()
    pool.join()


def main():
    host = 'quintoandardbprod-read1.ciuoqxapzjot.us-east-1.rds.amazonaws.com'
    port = '3306'
    database = 'ebdb'
    username = "bi"
    password = "paraguay-attorney-dignity"

    num_partitions = 16
    consumer = MysqlConsumer(host,
                             port,
                             database,
                             username,
                             password)

    tables_sizes = dict(consumer.get_table_names_and_sizes_from_source().collect())
    tables_sizes = {k: v for k, v in tables_sizes.items() if k not in black_list}

    spark.sql('CREATE DATABASE IF NOT EXISTS {}'.format(consumer.connection['db']))

    if op == 'full':
        big_tables = [table[0] for table in tables_sizes.items() if table[1] != None and table[1] > 200]
        small_tables = [table[0] for table in tables_sizes.items() if table[1] != None and table[1] <= 200]

        for table in big_tables:
            copy_big_table
        copy_big_tables(big_tables, num_partitions, consumer)
        copy_small_tables(small_tables, num_partitions, consumer)

    if op == 'daily':
        aud_tables = [table[0] for table in tables_sizes.items() if table[1] != None and table[0][-3:] == 'AUD']
        non_aud_tables = [table[0] for table in tables_sizes.items() if table[1] != None and table[0][-3:] != 'AUD']
        big_tables = [table[0] for table in tables_sizes.items() if
                      table[1] != None and table[0] not in aud_tables and table[1] > 200]
        small_tables = [table[0] for table in tables_sizes.items() if
                        table[1] != None and table[0] not in aud_tables and table[1] <= 200]

        copy_big_tables(big_tables, num_partitions, consumer)
        copy_small_tables(small_tables, num_partitions, consumer)
        aud_strategy(aud_tables, num_partitions, consumer)

    if op == 'pre_daily':
        aud_tables = [table[0] for table in tables_sizes.items() if table[1] != None and table[0][-3:] == 'AUD']
        aud_strategy(aud_tables, num_partitions, consumer, pre_daily=True)


if __name__ == '__main__':
    main()
