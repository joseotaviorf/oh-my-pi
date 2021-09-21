import json
import logging

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.service import ServiceEnum
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.base.spark.spark_metastore_helper import (
    SparkMetastoreHelper,
)
from bietlejuice.jobs.composer.pipeline.full_content_lineage_pipeline import (
    FullContentLineagePipeline,
)

JOB_NAME = "propagate_tables_metadata_clean_staging"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

BLOCK_LIST = ["subpartitions_values"]


def get_all_columns_lineage_from_events_table(spark_metastore_helper):
    spark_ms_table_columns = spark_metastore_helper.get_spark_metastore_table_columns(
        "events"
    )
    columns_lineage = {}
    for col_name, col_type in spark_ms_table_columns.items():
        columns_lineage[col_name] = {
            "lineage": [f"datalake_amplitude_clean.events.{col_name}"]
        }
    return columns_lineage


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
    logger.info(f"m={JOB_NAME}, msg=Job execution started.")

    spark_ms = SparkMetastoreHelper(
        "", LayerEnum.CLEAN_STAGING.value, "amplitude", None, True
    )

    spark_table_names = list(set(spark_ms.get_table_names()) - set(BLOCK_LIST))

    columns_lineage = get_all_columns_lineage_from_events_table(spark_ms)
    metadata_propagator = MetadataPropagator(
        get_metadata_propagator_host(), spark_ms.spark_database_name, columns_lineage
    )

    rdd = BaseSparkContext.sc.parallelize(spark_table_names)
    rdd.foreach(lambda table_name: metadata_propagator.propagate_table(table_name))

    logger.info(f"m={JOB_NAME}, msg=Job finished.")
