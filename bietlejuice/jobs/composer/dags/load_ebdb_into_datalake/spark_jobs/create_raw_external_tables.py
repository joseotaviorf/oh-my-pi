from python_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl.load_ebdb_into_datalake.ebdb_into_datalake_loader import EBDBIntoDatalakeLoader, \
    execute_athena_query, get_athena_client

logger = QuintoAndarLogger('create_raw_external_tables')

if __name__ == '__main__':
    athena_db = EBDBIntoDatalakeLoader.ATHENA_RAW_SCHEMA
    execute_athena_query(get_athena_client(), 'CREATE DATABASE IF NOT EXISTS {}'.format(athena_db))
    databricks_consumer = DatabricksConsumer('ebdb')
    response = databricks_consumer.get_table_names_and_sizes()
    tables = response.select('tableName').collect()

    datalake_loader = EBDBIntoDatalakeLoader()

    logger.info('m=__main__, msg=Creating raw external tables...')
    for table in tables:
        table_name = table.tableName
        datalake_loader.create_athena_external_table(databricks_consumer,
                                                     table_name,
                                                     ['dt'] if '_aud' in table_name.lower() else None)

    logger.info('m=__main__, msg=All raw external tables were created successfully.')
