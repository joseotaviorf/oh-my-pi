from argparse import ArgumentParser
from datetime import datetime
from collections import OrderedDict
from multiprocessing.dummy import Pool
import logging

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.clients.db_clients import AthenaClient
from bietlejuice.jobs.composer.services.metastore_services import AthenaMetastoreService
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.db import QUERIES_DATALAKE_PATH

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "upsert_table_partition"
SOURCE = "bigfone"
NB_THREADS = 5

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def add_partition(args):
    athena_metastore_service, db, table_name, dt_execution, event = args
    partition_by_dict = OrderedDict(
        [
            ("year", dt_execution.year),
            ("month", dt_execution.month),
            ("day", dt_execution.day),
            ("event", event),
        ]
    )
    athena_metastore_service.add_partitions(db, table_name, [partition_by_dict])


if __name__ == "__main__":

    parser = ArgumentParser(description="{}".format(JOB_NAME))

    # args passed by Airflow task
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()

    logger.info(
        "m=create_external_table, execution_date={}, environment={}, msg=print args spark jobs params".format(
            args.execution_date, args.environment
        )
    )

    execution_date = args.execution_date
    environment = args.environment
    table_name = "events"

    datalake_info = DatalakeMetastoreService().get_db_info(environment, SOURCE)
    dt_execution = datetime.strptime(execution_date, "%Y-%m-%d")

    query = FileService.get_query_from_file_name(
        QUERIES_DATALAKE_PATH + "bigfone_event/event_type.sql"
    )

    spark_client = SparkClient()

    df = spark_client.get_records(
        query=query.format(
            db=datalake_info["db_clean_databricks"],
            table_name=table_name,
            column="event",
            year=dt_execution.year,
            month=dt_execution.month,
            day=dt_execution.day,
        )
    )

    athena_client = AthenaClient()
    athena_metastore_service = AthenaMetastoreService(athena_client)

    with Pool(NB_THREADS) as p:
        p.map(
            add_partition,
            [
                (
                    athena_metastore_service,
                    datalake_info["db_clean_athena"],
                    table_name,
                    dt_execution,
                    row["event"],
                )
                for row in df.collect()
            ],
        )
