import logging

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl import DataSourceIntoDataLakeLoader
from bietlejuice.jobs.composer.wrappers import AthenaClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger('create_raw_external_tables')

ATHENA_DB = 'datalake_raw_spark'
RAW_PATH = 's3://5a-datalake/raw_spark/docx'

if __name__ == '__main__':
    AthenaClient.execute_athena_query('CREATE DATABASE IF NOT EXISTS `{}`'.format(ATHENA_DB), 'default')
    connection = {
        'db': 'docx'
    }
    databricks_consumer = DatabricksConsumer(connection)
    df = databricks_consumer.get_table_names_and_sizes()
    tables = df.select('tableName').collect()

    logger.info('m=__main__, msg=Creating raw external tables...')
    for table in tables:
        table_name = 'docx_{}'.format(table.tableName)
        DataSourceIntoDataLakeLoader.create_athena_external_table(
            consumer=databricks_consumer,
            table=table_name,
            raw_path=RAW_PATH,
            athena_raw_schema=ATHENA_DB
        )

    logger.info('m=__main__, msg=All raw external tables were created successfully.')
