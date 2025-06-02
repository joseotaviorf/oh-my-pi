import json

from argparse import ArgumentParser, Namespace
from multiprocessing.pool import ThreadPool
from bietlejuice.base.db import MetastoreMappingFactory
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.loaders.delta_loader import DeltaLoader
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "optimize_delta_table"
logger = QuintoAndarLogger(JOB_NAME)


def main():
    args = parse_arguments()
    loader = DeltaLoader(spark)
    tables = json.loads(args.tables)
    logger.info(f"Starting vacuum and optimize for {len(tables)} tables, parallelism = {args.parallelism}.")
    pool = ThreadPool(processes=args.parallelism)
    pool.starmap(
        run_job,
        [
            (loader, table_name, table_configs, args.layer)
            for table_name, table_configs in tables.items()
        ],
    )

    logger.info("Vacuum and optimize finished for all tables.")


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
    parser.add_argument(
        "parallelism",
        type=int,
        help="Number of parallel jobs to run. Default is 16.",
        default=16,
    )

    return parser.parse_args()


def run_job(
    loader: DeltaLoader, table_name: str, table_configs: dict, layer: str
) -> None:
    """Runs vacuum and, optionally, optimize on a given table."""

    full_table_name = get_full_table_name(
        table_configs.get("schema"), LayerEnum(layer), table_name
    )
    if table_configs.get("run_optimize", True):
        loader.optimize_table(full_table_name, table_configs.get("z_order_by", []))

    if table_configs.get("run_vacuum", True):
        if table_configs.get("vacuum_lite", False):
            loader.vacuum_lite_table(
                full_table_name, table_configs.get("vacuum_retention_hours", 7 * 24)
            )
        else:
            loader.vacuum_table(
                full_table_name, table_configs.get("vacuum_retention_hours", 7 * 24)
            )


def get_full_table_name(schema: str, layer: LayerEnum, table_name: str) -> str:
    """Returns the full table name in the format database_name.table_name."""

    metastore_mapping_factory = MetastoreMappingFactory.get_mapper_by_layer(
        layer, schema, ""
    )
    database_name = metastore_mapping_factory.get_full_database_name(layer)
    return f"{database_name}.{table_name}"


if __name__ == "__main__":
    main()
