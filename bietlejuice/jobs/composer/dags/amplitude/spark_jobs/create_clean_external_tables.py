import logging
from argparse import ArgumentParser
from multiprocessing.dummy import Pool

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.airflow.environment import Environment
from bietlejuice.jobs.composer.consumers import DatabricksConsumer
from bietlejuice.jobs.composer.etl.amplitude import AmplitudeEvents
from bietlejuice.jobs.composer.wrappers import AthenaClient

JOB_NAME = "create_clean_external_tables"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

NB_THREADS = 11


def get_s3_clean_path(environment):
    if not Environment.is_valid_environment(environment):
        raise RuntimeError(
            "msg=environment %s invalid. Environments allowed are: "
            % ", ".join(Environment.get_valid_environments())
        )
    return "s3://5a-datalake-{}/clean/amplitude/".format(environment)


def create_clean_external_table(args):
    table_name, table_extra_partitions, amplitude_events, databricks_consumer, athena_db = (
        args
    )
    partition_by = ["year", "month", "day"]
    if table_name in table_extra_partitions:
        partition_by = partition_by + table_extra_partitions[table_name]
    amplitude_events.create_athena_external_table(
        consumer=databricks_consumer,
        table=table_name,
        athena_db=athena_db,
        partition_by=partition_by,
    )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env")
    args = parser.parse_args()
    environment = args.env

    db_clean = "datalake_amplitude_clean"
    s3_clean_path = get_s3_clean_path(environment)
    amplitude_events = AmplitudeEvents(db_clean=db_clean, s3_clean_path=s3_clean_path)

    athena_db = "{}_{}".format(db_clean, environment)
    AthenaClient.execute_athena_query(
        "CREATE DATABASE IF NOT EXISTS `{}`".format(athena_db), "default"
    )

    connection = {"db": db_clean}
    databricks_consumer = DatabricksConsumer(connection)
    tables = databricks_consumer.get_table_names_and_sizes().collect()
    table_extra_partitions = {"amplitude_events": ["event_type"]}

    logger.info("m=__main__, msg=Creating clean external tables...")

    with Pool(NB_THREADS) as p:
        p.map(
            create_clean_external_table,
            [
                (
                    table.table_name,
                    table_extra_partitions,
                    amplitude_events,
                    databricks_consumer,
                    athena_db,
                )
                for table in tables
            ],
        )
    logger.info("m=__main__, msg=All raw external tables were created successfully.")
