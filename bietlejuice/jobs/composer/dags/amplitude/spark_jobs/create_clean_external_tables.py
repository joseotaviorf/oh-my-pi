import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.wrappers import AthenaClient
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger("create_clean_external_tables")

parser = ArgumentParser(description='create_clean_external_tables')
parser.add_argument('env')


def get_s3_clean_path(env):
    if env == 'forno':
        return 's3://5a-datalake-forno/clean_spark/amplitude/'
    elif env == 'prod':
        return 's3://5a-datalake/clean_spark/amplitude/'
    raise ValueError('The environment do not exists: {}'.format(env))


if __name__ == '__main__':
    args = parser.parse_args()
    env = args.env

    db_clean = 'datalake_clean_spark'
    s3_clean_path = get_s3_clean_path(env)
    amplitude_events = AmplitudeEvents(db_clean=db_clean, s3_clean_path=s3_clean_path)

    athena_db = amplitude_events.db_clean
    AthenaClient.execute_athena_query('CREATE DATABASE IF NOT EXISTS `{}`'.format(athena_db), 'default')

    connection = {'db': db_clean}
    databricks_consumer = DatabricksConsumer(connection)
    df = databricks_consumer.get_table_names_and_sizes(table_name_match='amplitude_%')
    tables = df.select("table_name").collect()
    table_extra_partitions = {'amplitude_events': ['event_type']}

    logger.info('m=__main__, msg=Creating clean external tables...')
    for table in tables:
        table_name = table.table_name
        partition_by = ['year', 'month', 'day']
        if table_name in table_extra_partitions:
            partition_by = partition_by + table_extra_partitions[table_name]
        amplitude_events.create_athena_external_table(consumer=databricks_consumer,
                                                      table=table_name,
                                                      partition_by=partition_by)
    logger.info("m=__main__, msg=All raw external tables were created successfully.")
