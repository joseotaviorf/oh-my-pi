import json
from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service import ServiceEnum
from bietlejuice.base.spark.spark_metastore_helper import SparkMetastoreHelper
from bietlejuice.base.spark import BaseSparkContext
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.metadata_propagator_pipeline.full_content_lineage_pipeline import (
    FullContentLineagePipeline,
)
from bietlejuice.services.metastore_services import SparkMetastoreService

DAYS_TO_CHECK_FOR_NEW_TABLES = 4

JOB_NAME = "propagate_tables_metadata_clean_staging"

logger = QuintoAndarLogger(JOB_NAME)

BLOCK_LIST = ["subpartitions_values"]


def get_all_columns_lineage_from_events_table(spark_metastore_helper):
    spark_ms_table_columns = spark_metastore_helper.get_spark_metastore_table_columns(
        "events"
    )
    columns_lineage = {}
    for col_name in spark_ms_table_columns.keys():
        columns_lineage[col_name] = {
            "lineage": [f"datalake_amplitude_clean.events.{col_name}"]
        }
    return columns_lineage


def is_new_table(execution_date, table_created_time):
    table_created_date = datetime.strptime(
        table_created_time, "%a %b %d %H:%M:%S UTC %Y"
    )
    if (execution_date - table_created_date).days < DAYS_TO_CHECK_FOR_NEW_TABLES:
        return True
    return False


def get_all_new_tables(spark_metastore_helper, execution_date):
    spark_metastore_service = SparkMetastoreService(SparkClient())

    all_table_names = list(
        set(spark_metastore_helper.get_table_names()) - set(BLOCK_LIST)
    )

    new_tables = []
    for table_name in all_table_names:
        table_created_time = spark_metastore_service.get_table_created_time(
            spark_metastore_helper.spark_database_name, table_name
        )
        if is_new_table(execution_date, table_created_time):
            new_tables.append(table_name)
    return new_tables


def get_metadata_propagator_host():
    metadata_propagator_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", ServiceEnum.METADATA_PROPAGATOR.value
    )
    return json.loads(metadata_propagator_confs)["host"]


class MetadataPropagator:
    def __init__(
        self, metadata_propagator_host, database_name, columns_lineage
    ) -> None:
        self.metadata_propagator_host = metadata_propagator_host
        self.database_name = database_name
        self.columns_lineage = columns_lineage

    def propagate_table(self, table_name):
        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, database_name={self.database_name}, "
            f"table_name={table_name} "
            f"msg=Starting table metadata propagation."
        )
        FullContentLineagePipeline(
            metadata_propagator_host=self.metadata_propagator_host,
            database_name=self.database_name,
            table_name=table_name,
            columns_lineage=self.columns_lineage,
        ).run()

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, database_name={self.database_name}, "
            f"table_name={table_name} "
            f"msg=Table metadata propagated."
        )


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("execution_date_str")

    args = parser.parse_args()
    execution_date_str = args.execution_date_str

    logger.info(f"m={JOB_NAME}, msg=Job execution started.")

    execution_date = datetime.strptime(execution_date_str, "%Y-%m-%d")

    spark_ms = SparkMetastoreHelper(
        "", LayerEnum.CLEAN_STAGING.value, "amplitude", None, True
    )

    table_names = get_all_new_tables(spark_ms, execution_date)

    if table_names:
        columns_lineage = get_all_columns_lineage_from_events_table(spark_ms)
        metadata_propagator = MetadataPropagator(
            get_metadata_propagator_host(),
            spark_ms.spark_database_name,
            columns_lineage,
        )

        rdd = BaseSparkContext.sc.parallelize(table_names)
        rdd.foreach(lambda table_name: metadata_propagator.propagate_table(table_name))

    logger.info(f"m={JOB_NAME}, msg=Job finished.")
