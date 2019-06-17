import json
import logging
from multiprocessing.dummy import Pool as ThreadPool

from python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base import DatabaseEnum, BaseDBUtils
from bietlejuice.jobs.composer.consumers import MySQLConsumer
from bietlejuice.jobs.composer.etl.load_docx_into_datalake import DocxIntoDatalakeLoader

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger('load_docx_into_datalake')

SIZE_THRESHOLD = 1024  # size in mb to decide if a table is big
NUM_PARTITIONS = 8  # max parallel connections to use when reading a table in jdbc
BLACK_LIST = ['flyway_schema_history']


@logger
def full_small_table_map_function(args):
    table, consumer = args
    logger.info('m=full_small_table_map_function, table={}, msg=Starting loading'
                'table.'.format(table))
    DocxIntoDatalakeLoader.load_full_table_into_datalake_raw(table, consumer)
    logger.info('m=full_small_table_map_function, table={}, msg=Finished loading table.'.format(table))


@logger
def load_full_small_tables(tables, threads_nb, consumer):
    logger.info('m=load_full_small_tables, msg=Starting loading small tables...')
    args = [(table, consumer) for table in tables]
    pool = ThreadPool(threads_nb)
    pool.map(full_small_table_map_function, args)
    pool.close()
    pool.join()
    logger.info('m=load_full_small_tables, msg=Finished loading small tables.')


@logger
def load_full_big_tables(tables, num_partitions, consumer):
    logger.info(
        'm=load_full_big_tables, msg=Starting loading big tables...')
    for table in tables:
        DocxIntoDatalakeLoader.load_full_table_into_datalake_raw(table=table,
                                                                 consumer=consumer,
                                                                 concurrency=num_partitions)
    logger.info(
        'm=load_full_big_tables, msg=Finished loading big tables.')


if __name__ == '__main__':
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    connection_json = dbutils.secrets.get(scope='quintoandar-forno', key=DatabaseEnum.DOCX)
    connection = json.loads(connection_json)
    mysql_consumer = MySQLConsumer(connection)

    tables_sizes = dict(DocxIntoDatalakeLoader.get_table_names_and_sizes(mysql_consumer).collect())
    tables_sizes = {k: v for k, v in tables_sizes.items() if k not in BLACK_LIST}  # filter out blacklist

    big_tables = [table[0] for table in tables_sizes.items() if
                  table[1] is not None and table[1] > SIZE_THRESHOLD]
    small_tables = [table[0] for table in tables_sizes.items() if
                    table[1] is not None and table[1] <= SIZE_THRESHOLD]

    load_full_big_tables(big_tables, NUM_PARTITIONS, mysql_consumer)
    load_full_small_tables(small_tables, NUM_PARTITIONS, mysql_consumer)
