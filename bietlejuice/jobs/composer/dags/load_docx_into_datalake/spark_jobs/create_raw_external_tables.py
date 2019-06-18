import logging

from quintoandar.python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl.load_docx_into_datalake import DocxIntoDatalakeLoader
from bietlejuice.jobs.composer.wrappers import AthenaClient

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger('create_raw_external_tables')

if __name__ == '__main__':
    athena_db = DocxIntoDatalakeLoader.ATHENA_RAW_SCHEMA
    AthenaClient.execute_athena_query('CREATE DATABASE IF NOT EXISTS `{}`'.format(athena_db), 'default')
    connection = {
        'db': 'docx'
    }
    databricks_consumer = DatabricksConsumer(connection)
    response = databricks_consumer.get_table_names_and_sizes()
    tables = response.select('tableName').collect()

    logger.info('m=__main__, msg=Creating raw external tables...')
    for table in tables:
        table_name = table.tableName
        DocxIntoDatalakeLoader.create_athena_external_table(consumer=databricks_consumer,
                                                            table=table_name)

    logger.info('m=__main__, msg=All raw external tables were created successfully.')
