import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.base.service import ServiceEnum
from bietlejuice.jobs.composer.base.spark import BaseSparkContext
from bietlejuice.jobs.composer.base.spark.spark_metastore_helper import (
    SparkMetastoreHelper,
)
from bietlejuice.jobs.composer.metadata_propagator_pipeline.lineage_tags_pipeline import (
    LineageTagsPipeline,
)
from bietlejuice.jobs.composer.metadata_propagator_pipeline.raw_lineage_pipeline import (
    RawLineagePipeline,
)
from bietlejuice.jobs.composer.services import FileService

JOB_NAME = "propagate_raw_tables_metadata"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def get_all_tables_metadata(spark_metastore_helper, metadata_type, relative_file_path):
    """
    Fetches all database tables metadata for the specified metadata type (tags or lineage)
    This metadata will be shared during the parallelized processing of table names RDD.
    """
    tables_spark_metadata = dict()
    for table_name in spark_metastore_helper.get_table_names():

        if metadata_type == MetadataTypeEnum.FULL_CONTENT_LINEAGE:
            spark_ms_table_columns = spark_metastore_helper.get_spark_metastore_table_columns(
                table_name
            )
            tables_spark_metadata[table_name] = dict()
            tables_spark_metadata[table_name]["name"] = table_name
            tables_spark_metadata[table_name]["columns"] = spark_ms_table_columns

        elif (
            metadata_type == MetadataTypeEnum.TAGS
            and FileService.metadata_file_exists(relative_file_path, layer, table_name)
        ):
            tables_spark_metadata[table_name] = dict()
            tables_spark_metadata[table_name]["name"] = table_name
    return tables_spark_metadata


def get_metadata_propagator_host():
    metadata_propagator_confs = dbutils.secrets.get(  # noqa: F821
        "quintoandar", ServiceEnum.METADATA_PROPAGATOR.value
    )
    return json.loads(metadata_propagator_confs)["host"]


class MetadataPropagator:
    def __init__(
        self,
        metadata_propagator_host,
        layer,
        metadata_type,
        database_name,
        product_database_name=None,
    ) -> None:
        self.metadata_propagator_host = metadata_propagator_host
        self.layer = layer
        self.metadata_type = metadata_type
        self.database_name = database_name
        self.product_database_name = product_database_name

    def propagate_table(self, table_spark_metadata):
        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, layer={self.layer}, database_name={self.database_name}, "
            f"table_name={table_spark_metadata['name']}, metadata_type={self.metadata_type}, "
            f"msg=Starting table metadata propagation."
        )

        if self.metadata_type == MetadataTypeEnum.TAGS:
            LineageTagsPipeline(
                metadata_propagator_host=self.metadata_propagator_host,
                database_name=self.database_name,
                table_name=table_spark_metadata["name"],
                metadata_type=self.metadata_type,
            ).run()

        if self.metadata_type == MetadataTypeEnum.FULL_CONTENT_LINEAGE:
            RawLineagePipeline(
                metadata_propagator_host=self.metadata_propagator_host,
                database_name=self.database_name,
                table_name=table_spark_metadata["name"],
                table_schema=table_spark_metadata["columns"],
                product_database_name=self.product_database_name,
            ).run()

        QuintoAndarLogger(JOB_NAME).info(
            f"m={JOB_NAME}, layer={self.layer}, database_name={self.database_name}, "
            f"table_name={table_spark_metadata['name']}, metadata_type={self.metadata_type}, "
            f"product_database_name={self.product_database_name}"
            f"msg=Table metadata propagated."
        )


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("layer_value", type=str, help="One of LayerEnum values")
    parser.add_argument(
        "metadata_type_value", type=str, help="One of MetadataTypeEnum values"
    )
    parser.add_argument("target_database_base_name", type=str)
    parser.add_argument("relative_file_path", type=str)
    parser.add_argument(
        "--product-database-name",
        type=str,
        dest="product_database_name",
        required=False,
        help="product database name, used in product to raw lineage",
    )
    parser.add_argument(
        "--table-name",
        type=str,
        dest="table_name",
        required=False,
        help="table name for single propagation",
    )
    parser.add_argument(
        "--all-tables",
        nargs="?",
        dest="all_tables",
        required=False,
        default=False,
        const=True,
        help="propagate all tables' metadata from database",
    )

    args = parser.parse_args()
    _layer_value = args.layer_value
    _metadata_type_value = args.metadata_type_value
    _target_database_base_name = args.target_database_base_name
    _relative_file_path = args.relative_file_path
    _product_database_name = args.product_database_name
    _table_name = args.table_name
    _all_tables = args.all_tables

    return (
        _layer_value,
        _metadata_type_value,
        _target_database_base_name,
        _relative_file_path,
        _product_database_name,
        _table_name,
        _all_tables,
    )


if __name__ == "__main__":
    (
        layer_value,
        metadata_type_value,
        target_database_base_name,
        relative_file_path,
        product_database_name,
        table_name,
        all_tables,
    ) = parse_args()

    layer = LayerEnum(layer_value).value
    metadata_type = MetadataTypeEnum(metadata_type_value)

    if metadata_type == MetadataTypeEnum.FULL_CONTENT_LINEAGE and (
        not product_database_name
    ):
        error_msg = (
            f"m={JOB_NAME}, metadata_type={metadata_type}, "
            f"product_database_name={product_database_name}, "
            f"msg=Product_database_name must be provided when metadata type is full_content_lineage"
        )
        logger.error(error_msg)
        raise ValueError(error_msg)

    logger.info(
        f"m={JOB_NAME}, "
        f"layer={layer}, metadata_type={metadata_type}, target_database_base_name={target_database_base_name}, "
        f"table_name={table_name}, all_tables={all_tables}, msg=Job execution started."
    )

    spark_ms = SparkMetastoreHelper(
        "", layer, target_database_base_name, table_name, all_tables
    )
    spark_ms.validate_table_arguments()

    tables_metadata = get_all_tables_metadata(
        spark_ms, metadata_type, relative_file_path
    )
    spark_table_names = list(tables_metadata.keys())

    metadata_propagator = MetadataPropagator(
        get_metadata_propagator_host(),
        layer,
        metadata_type,
        spark_ms.spark_database_name,
        product_database_name,
    )

    rdd = BaseSparkContext.sc.parallelize(spark_table_names)
    rdd.foreach(
        lambda _table_name: metadata_propagator.propagate_table(
            tables_metadata.get(_table_name)
        )
    )

    logger.info(f"m={JOB_NAME}, msg=Job finished.")
