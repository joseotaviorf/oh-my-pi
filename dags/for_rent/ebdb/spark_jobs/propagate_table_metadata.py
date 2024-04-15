import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreMapping, MetricMetastoreMapping
from bietlejuice.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.base.service import ServiceEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.metadata_propagator_pipeline.lineage_tags_pipeline import (
    LineageTagsPipeline,
)

JOB_NAME = "propagate_table_metadata"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("layer_value", type=str, help="One of LayerEnum values")
    parser.add_argument(
        "metadata_type_value", type=str, help="One of MetadataTypeEnum values"
    )
    parser.add_argument(
        "db_name_part",
        type=str,
        help="The `source` name for clean layer."
        " The `source` and/or `context` name for enrich layer. The `schema` for DW layer.",
    )
    parser.add_argument("table_name", type=str, help="table name")

    args = parser.parse_args()

    layer = LayerEnum(args.layer_value).value
    metadata_type = MetadataTypeEnum(args.metadata_type_value)
    db_name_part = args.db_name_part
    table_name = args.table_name

    logger.info(
        f"m={JOB_NAME}, layer={layer}, metadata_type={metadata_type}, db_name_part={db_name_part}, "
        f"table_name={table_name},  msg=Job execution started."
    )

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    metadata_propagator_confs = dbutils.secrets.get(
        "quintoandar", ServiceEnum.METADATA_PROPAGATOR.value
    )
    metadata_propagator_confs_json = json.loads(metadata_propagator_confs)

    if layer == LayerEnum.DW.value:
        dw_ms_mapping = DwMetastoreMapping(
            source=db_name_part, bucket=""
        ).get_all_dw_info()
        database_name = dw_ms_mapping["dw_schema_databricks"]
    elif layer == LayerEnum.METRIC.value:
        metric_ms_mapping = MetricMetastoreMapping(source=db_name_part, bucket="")
        database_name, _ = metric_ms_mapping.get_metric_info()
    else:
        dl_ms_mapping = DatalakeMetastoreMapping(source=db_name_part, bucket="")
        database_name, _ = dl_ms_mapping.get_datalake_info_from_layer(layer)

    LineageTagsPipeline(
        metadata_propagator_host=metadata_propagator_confs_json["host"],
        database_name=database_name,
        table_name=table_name,
        metadata_type=metadata_type,
    ).run()

    logger.info(
        f"m={JOB_NAME}, layer={layer}, metadata_type={metadata_type}, db_name_part={db_name_part}, "
        f"table_name={table_name}, msg=Metadata propagated to Atlas."
    )
