"""
Configuration management for QUBE jobs.
Supports environment variables and .env files.
"""

import argparse
import os
from typing import Any, Dict, Optional


class Config:
    """Configuration for QUBE jobs with environment variable support."""

    def __init__(
        self,
        env: str = "dev",
        config_root: str = "qube/specs",
        db_prefix: str = "",
        warehouse: Optional[str] = None,
    ):
        self.env = env
        self.config_root = config_root
        self.db_prefix = db_prefix

        # Database / Namespace configuration (configurable via env vars)
        core_db_base = os.getenv("QUBE_CORE_DB", "core")
        dim_db_base = os.getenv("QUBE_DIM_DB", "qube_dimensions")
        meas_db_base = os.getenv("QUBE_MEAS_DB", "qube_measures")
        met_db_base = os.getenv("QUBE_MET_DB", "qube_metrics")

        # Apply Unity Catalog prefix for Databricks environments
        if env in ["forno", "prod"]:
            catalog = f"quintoandar_{env}"
            self.core_db = f"{catalog}.{core_db_base}"
            self.dim_db = f"{catalog}.{dim_db_base}"
            self.meas_db = f"{catalog}.{meas_db_base}"
            self.met_db = f"{catalog}.{met_db_base}"
        else:
            self.core_db = core_db_base
            self.dim_db = dim_db_base
            self.meas_db = meas_db_base
            self.met_db = met_db_base

        # Apply additional prefix if provided (for test environments)
        if db_prefix:
            self.core_db = f"{db_prefix}{self.core_db}"
            self.dim_db = f"{db_prefix}{self.dim_db}"
            self.meas_db = f"{db_prefix}{self.meas_db}"
            self.met_db = f"{db_prefix}{self.met_db}"

        # Warehouse path configuration
        if warehouse:
            self.warehouse_path = warehouse
        else:
            if env == "forno":
                self.warehouse_path = "s3a://5a-datalake-forno"
            elif env == "prod":
                self.warehouse_path = "s3a://5a-datalake-prod"
            else:
                # Dev, test, local environments
                self.warehouse_path = os.getenv("QUBE_WAREHOUSE_PATH", "/tmp/warehouse")

    def get_table_path(self, layer: str, table_name: str) -> str:
        """
        Returns the full table identifier or path.

        Args:
            layer: Layer type ('core', 'dim', 'meas', 'met')
            table_name: Table name (with or without database prefix)

        Returns:
            Fully qualified table name (database.table)
        """
        db_map = {
            "core": self.core_db,
            "dim": self.dim_db,
            "meas": self.meas_db,
            "met": self.met_db,
        }
        db = db_map.get(layer, "default")

        # If table_name already has a dot, assume it's fully qualified
        if table_name and "." in table_name:
            return table_name

        return f"{db}.{table_name}"

    def get_schema_name(self, layer: str) -> str:
        """
        Extract schema name without catalog prefix for file path construction.

        Args:
            layer: Layer type ('core', 'dim', 'meas', 'met')

        Returns:
            Schema name without catalog prefix (e.g., "qube_dimensions" from "quintoandar_forno.qube_dimensions")
        """
        db_map = {
            "core": self.core_db,
            "dim": self.dim_db,
            "meas": self.meas_db,
            "met": self.met_db,
        }
        full_db_name = db_map.get(layer, "default")

        # If database name has catalog prefix (e.g., "quintoandar_forno.qube_dimensions"),
        # extract just the schema name
        if "." in full_db_name and full_db_name.startswith("quintoandar_"):
            return full_db_name.split(".", 1)[1]

        return full_db_name

    def to_dict(self) -> Dict[str, Any]:
        """Export configuration as dictionary for logging."""
        return {
            "env": self.env,
            "config_root": self.config_root,
            "core_db": self.core_db,
            "dim_db": self.dim_db,
            "meas_db": self.meas_db,
            "met_db": self.met_db,
            "warehouse_path": self.warehouse_path,
        }


def parse_common_args(description: str) -> argparse.Namespace:
    """
    Parse common command-line arguments for QUBE jobs.

    Args:
        description: Job description for help text

    Returns:
        Parsed arguments namespace
    """
    parser = argparse.ArgumentParser(
        description=description,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
                Examples:
                # Build dimension for specific date
                python build_dimension.py --spec specs/dimensions/visit_status.yaml --date 2025-06-29
                # Build with custom environment
                python build_dimension.py --spec specs/dimensions/visit_status.yaml --env prod
                # Use custom database prefix
                python build_dimension.py --spec specs/dimensions/visit_status.yaml --db-prefix test_
        """,
    )

    parser.add_argument(
        "--date",
        required=False,
        help="YYYY-MM-DD window end date (optional, defaults to max date in source)",
    )
    parser.add_argument(
        "--entity",
        required=False,
        help="Entity type (e.g., visit, offer). Optional if defined in spec.",
    )
    spec_group = parser.add_mutually_exclusive_group(required=True)
    spec_group.add_argument("--spec", help="Path to YAML spec file")
    spec_group.add_argument(
        "--spec-json",
        help="Spec content as JSON string (alternative to --spec file path)",
    )
    parser.add_argument(
        "--env",
        default=os.getenv("QUBE_ENV", "dev"),
        help="Environment (dev, test, prod). Default: %(default)s",
    )
    parser.add_argument(
        "--config-root",
        default="qube/specs",
        help="Root directory for specs. Default: %(default)s",
    )
    parser.add_argument(
        "--warehouse",
        default=None,
        help="Warehouse location (overrides QUBE_WAREHOUSE_PATH env var)",
    )
    parser.add_argument(
        "--db-prefix",
        default=os.getenv("QUBE_DB_PREFIX", ""),
        help="Prefix for database names. Default: %(default)s",
    )
    parser.add_argument(
        "--log-level",
        default=os.getenv("LOG_LEVEL", "INFO"),
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Logging level. Default: %(default)s",
    )
    parser.add_argument(
        "--log-format",
        default=os.getenv("LOG_FORMAT", "standard"),
        choices=["standard", "json"],
        help="Log format. Default: %(default)s",
    )
    parser.add_argument(
        "-tdn",
        "--target-database-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
        help="Validation target database (cluster_validation). When set together with "
        "--target-table-name, writes are redirected to the validation schema instead "
        "of the production qube_* database.",
    )
    parser.add_argument(
        "-ttn",
        "--target-table-name",
        type=lambda arg: None if not arg else arg,
        required=False,
        default=None,
        help="Validation target table name (prod_database___table). When set together "
        "with --target-database-name, writes are redirected to the validation schema.",
    )

    return parser.parse_args()
