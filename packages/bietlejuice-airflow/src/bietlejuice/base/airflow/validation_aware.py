from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.validation.target_resolver import (
    get_prod_database_name,
    resolve_validation_target,
)


def validation_spark_extra_args(
    is_validation: bool, layer: LayerEnum, schema: str, table_name: str
) -> list:
    if not is_validation:
        return []
    prod_db = get_prod_database_name(layer, schema)
    target_db, target_table = resolve_validation_target(prod_db, table_name)
    return [
        "--target-database-name",
        target_db,
        "--target-table-name",
        target_table,
    ]
