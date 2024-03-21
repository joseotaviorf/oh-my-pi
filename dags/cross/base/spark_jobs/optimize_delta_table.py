import json

from argparse import ArgumentParser, Namespace
from bietlejuice.base.db import MetastoreMappingFactory
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.loaders.delta_loader import DeltaLoader
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "optimize_delta_table"
logger = QuintoAndarLogger(JOB_NAME)


def main():
    args = parse_arguments()
    loader = DeltaLoader()

    for table_name, table_configs in json.loads(args.tables).items():
        full_table_name = get_full_table_name(
            table_configs.get("schema"), LayerEnum(args.layer), table_name
        )
        if table_configs.get("run_optimize", True):
            loader.optimize_table(full_table_name, table_configs.get("z_order_by", []))
        loader.vacuum_table(full_table_name, table_configs.get("vacuum_retention_hours", 7 * 24))

    logger.info("Vacuum and optimize finished for all tables.")


def get_full_table_name(schema: str, layer: LayerEnum, table_name: str) -> list:
    metastore_mapping_factory = MetastoreMappingFactory.get_mapper_by_layer(
        layer, schema, ""
    )
    database_name = metastore_mapping_factory.get_full_database_name(layer)
    return f"{database_name}.{table_name}"


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("layer", type=str, help="Layer of the tables")
    parser.add_argument(
        "tables",
        type=str,
        help="JSON object with all tables to vacuum and optimize. Each key is a table name, "
        "and each value is an object with the following attributes: schema (string), vacuum_retention_hours (integer), "
        "z_order_by(list), and run_optimize(boolean)",
    )

    return parser.parse_args()


if __name__ == "__main__":
    main()
