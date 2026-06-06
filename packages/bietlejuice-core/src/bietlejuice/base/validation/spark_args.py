from argparse import ArgumentParser
from typing import Optional, Tuple


def add_validation_target_args(parser: ArgumentParser) -> None:
    """Register optional flags appended by LoadCustomTaskCreator in validation mode."""
    parser.add_argument(
        "--target-database-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )
    parser.add_argument(
        "--target-table-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
    )


def is_validation_run(
    target_database: Optional[str],
    target_table: Optional[str],
) -> bool:
    """True when Airflow passed cluster-validation write-target flags."""
    return bool(target_database and target_table)


def resolve_datalake_write_target(
    *,
    prod_database: str,
    prod_table: str,
    prod_location: str,
    bucket: str,
    target_database: Optional[str],
    target_table: Optional[str],
) -> Tuple[str, str, str]:
    """Return (write_database, write_table, write_location)."""
    if target_database and target_table:
        from bietlejuice.base.validation.target_resolver import (
            validation_database_location,
        )

        return (
            target_database,
            target_table,
            validation_database_location(bucket, prod_database),
        )
    return prod_database, prod_table, prod_location
