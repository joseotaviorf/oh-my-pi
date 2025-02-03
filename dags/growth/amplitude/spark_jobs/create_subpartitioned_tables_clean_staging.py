from argparse import ArgumentParser
from datetime import datetime
from functools import reduce
from urllib.parse import unquote

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.spark import spark, sqlContext
from bietlejuice.clients.db_clients.spark_client import SparkClient
from bietlejuice.formatters.string_formatter import StringFormatter
from bietlejuice.services.metastore_services.spark_metastore_service import (
    SparkMetastoreService,
)

JOB_NAME = "create_subpartitioned_tables_clean_staging"

logger = QuintoAndarLogger(JOB_NAME)

parser = ArgumentParser(JOB_NAME)
parser.add_argument("execution_date")
parser.add_argument("env")
parser.add_argument("datalake_bucket")
parser.add_argument("source")
parser.add_argument("source_table_name")

ddl_template = """
    CREATE VIEW IF NOT EXISTS
        `{clean_staging_db}`.`{subpartitioned_table_name}`
    AS
    SELECT *
    FROM
        `{clean_staging_db}`.`{source_table_name}`
    WHERE
        id_app = {id_app}
        AND event_type =  '{event_type}'
"""


def create_subpartitioned_table(subpartitioned_table_name, row):
    logger.info(
        f"m=__main__, msg=Creating and repairing table '{subpartitioned_table_name}'..."
    )
    ddl = ddl_template.format(
        clean_staging_db=db_clean_staging,
        subpartitioned_table_name=subpartitioned_table_name,
        clean_db=db_info["db_clean_databricks"],
        source_table_name=source_table_name,
        id_app=row.id_app,
        event_type=row.event_type,
    )
    spark.sql(ddl)
    logger.info(
        f"m=__main__, msg=Table '{subpartitioned_table_name}' created and repaired."
    )
    spark_metastore_service.refresh_table(db_clean_staging, subpartitioned_table_name)


if __name__ == "__main__":
    # args
    args = parser.parse_args()
    execution_date = args.execution_date
    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    source_table_name = args.source_table_name

    logger.info(
        f"m=__main__, date={execution_date}, source={source}, "
        f"source_table_name={source_table_name}, msg=Job started"
    )

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day

    db_info = DatalakeMetastoreService.get_db_info(env, source, datalake_bucket)
    db_clean_staging = db_info["db_clean_staging_databricks"]

    # get subpartitions values
    subpartitions_values = sqlContext.table(
        f"{db_clean_staging}.subpartitions_values"
    ).collect()

    spark_metastore_service = SparkMetastoreService(SparkClient())

    # get existing tables
    spark_metastore_service.create_database(db_clean_staging)
    existing_tables = spark_metastore_service.get_table_names(db_clean_staging)

    # create clean staging subpartitioned tables
    for row in subpartitions_values:
        suffixed_table_name = "_".join(str(col) for col in row) + "_events"
        subpartitioned_table_name = StringFormatter.set_alphanumeric_snake_case(
            unquote(suffixed_table_name.replace("-", "_"))
        )
        if len(subpartitioned_table_name) < 128 and subpartitioned_table_name not in existing_tables:
            create_subpartitioned_table(subpartitioned_table_name, row)
        else:
            logger.info(
                f"m=__main__, msg=Table '{subpartitioned_table_name}' already exists."
            )
