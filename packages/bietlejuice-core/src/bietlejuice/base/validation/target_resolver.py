from typing import Optional

from bietlejuice.base.db.datalake_metastore_mapping import DatalakeMetastoreMapping
from bietlejuice.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.base.db.metric_metastore_mapping import MetricMetastoreMapping
from bietlejuice.base.db.qube_metastore_mapping import QubeMetastoreMapping
from bietlejuice.base.db.reverse_metastore_mapping import ReverseMetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum

CLUSTER_VALIDATION_SCHEMA = "cluster_validation"
_VALIDATION_TABLE_SEPARATOR = "___"


def get_prod_database_name(
    layer: LayerEnum,
    schema: str,
    bucket: str = "",
    transformation_grade: Optional[str] = None,
) -> str:
    # bucket is only used by metastore path helpers; UC database names depend on layer/schema.
    if layer == LayerEnum.METRIC:
        return MetricMetastoreMapping(
            bucket=bucket, source=schema
        ).get_full_database_name()
    if layer in (LayerEnum.DW, LayerEnum.DW_STAGING):
        return DwMetastoreMapping(bucket=bucket, source=schema).get_full_database_name(
            layer
        )
    if layer == LayerEnum.REVERSE:
        return ReverseMetastoreMapping(
            bucket=bucket, source=schema
        ).get_full_database_name()
    if layer == LayerEnum.QUBE:
        return QubeMetastoreMapping(
            source=schema, bucket=bucket
        ).get_full_database_name(layer)
    return DatalakeMetastoreMapping(
        bucket=bucket, source=schema
    ).get_full_database_name(layer, transformation_grade=transformation_grade)


def managed_table_fqn(
    prod_database: str,
    prod_table: str,
    target_database: Optional[str] = None,
    target_table: Optional[str] = None,
) -> str:
    """Fully qualified table for privileges/row-filter side effects (prod or validation)."""
    if target_database and target_table:
        return f"{target_database}.{target_table}"
    return f"{prod_database}.{prod_table}"


def resolve_validation_target(prod_database: str, table: str) -> tuple[str, str]:
    return (
        CLUSTER_VALIDATION_SCHEMA,
        f"{prod_database}{_VALIDATION_TABLE_SEPARATOR}{table}",
    )


def validation_database_location(bucket: str, prod_database: str) -> str:
    return f"s3a://{bucket}/validation/cluster_validation/{prod_database}/"


def validation_dw_database_location(bucket: str, prod_database: str) -> str:
    """DW layer uses s3:// paths from metastore; match prod write protocol."""
    return validation_database_location(bucket, prod_database).replace(
        "s3a://", "s3://"
    )
