import traceback
from argparse import ArgumentParser

from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.sst.core.metadata.sync_metadata import (
    set_logger,
    sync_trino_tables_metadata,
)

JOB_NAME = "sync_metadata"

base_logger = set_logger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("bucket", type=str)
    parser.add_argument("layer", type=str)
    parser.add_argument("schema", type=str)
    parser.add_argument(
        "--table-name",
        type=str,
        dest="table_name",
        required=False,
        help="table name for single sync",
    )
    parser.add_argument(
        "--all-tables",
        nargs="?",
        dest="all_tables_flag",
        required=False,
        default=False,
        const=True,
        help="flag to sync all tables from database",
    )

    args = parser.parse_args()
    bucket = args.bucket
    layer = LayerEnum(args.layer).value
    schema = args.schema
    table_name = args.table_name
    all_tables_flag = args.all_tables_flag

    try:
        sync_trino_tables_metadata(bucket, layer, schema, table_name, all_tables_flag)
    except Exception as e:
        base_logger.error(
            f"m={JOB_NAME}, msg=sync_trino_tables_metadata failed with:\n\n\n {e}"
        )
        base_logger.error(traceback.format_exc())
        raise
