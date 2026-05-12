import argparse
import json
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


class JobArgumentParser:
    """
    Parses and provides access to job parameters from command-line arguments.
    """

    @staticmethod
    def create_parser() -> argparse.ArgumentParser:
        """
        Creates and returns an argument parser for configuring the job parameters.

        Returns:
            argparse.ArgumentParser: A configured ArgumentParser object.
        """
        parser = argparse.ArgumentParser(description="Degreed Integration Pipeline")

        parser.add_argument("environment", help="Environment (e.g., forno, prod)")
        parser.add_argument("datalake_bucket", help="Target S3 bucket")
        parser.add_argument("dag_name", help="DAG name, default schema")
        parser.add_argument("table_name", help="Table name to process")
        parser.add_argument("execution_date", help="Execution date (YYYY-MM-DD)")
        parser.add_argument(
            "partitions", help="Partition columns (comma-separated or JSON list)"
        )
        parser.add_argument(
            "extraction_type", help="Extraction type (full, incremental)"
        )
        parser.add_argument("load_start_date", help="Start date (YYYY-MM-DD)")
        parser.add_argument("load_end_date", help="End date (YYYY-MM-DD)")
        parser.add_argument(
            "extra_details", nargs="?", default="{}", help="Extra details (JSON string)"
        )

        return parser

    @classmethod
    def parse_args(cls) -> dict:
        """
        Parses command-line arguments into a dictionary with extensive logging.

        Returns:
            dict: A dictionary containing the parsed command-line arguments.
        """
        parser = cls.create_parser()
        args = parser.parse_args()
        args_dict = vars(args)

        extra_details_str = args_dict.pop("extra_details", "{}")
        try:
            extra_details = json.loads(extra_details_str)
        except json.JSONDecodeError as e:
            LOGGER.error(
                f"Invalid JSON for extra_details: '{extra_details_str}'. Error: {e}"
            )
            raise

        args_dict.update(extra_details)

        if "base_filters" in args_dict and isinstance(args_dict["base_filters"], str):
            try:
                args_dict["base_filters"] = json.loads(args_dict["base_filters"])
            except json.JSONDecodeError as e:
                LOGGER.error(
                    f"Failed to parse 'base_filters' string: '{args_dict['base_filters']}'. Error: {e}"
                )
                raise

        for date_field in ["load_start_date", "load_end_date", "execution_date"]:
            date_str = args_dict.get(date_field)
            if date_str:
                try:
                    args_dict[date_field] = datetime.strptime(
                        date_str, "%Y-%m-%d"
                    ).date()
                except ValueError as e:
                    LOGGER.error(
                        f"Invalid date format for {date_field}: '{date_str}'. Expected YYYY-MM-DD. Error: {e}"
                    )
                    raise

        raw_partitions = args_dict.get("partitions")
        partition_cols = []
        if raw_partitions:
            raw_partitions = raw_partitions.strip()
            if raw_partitions and raw_partitions != "[]":
                try:
                    parsed = json.loads(raw_partitions)
                    if isinstance(parsed, list) and all(
                        isinstance(p, str) for p in parsed
                    ):
                        partition_cols = [col.strip() for col in parsed if col.strip()]
                    else:
                        LOGGER.warning(
                            "Partitions string is valid JSON but not a list of strings. Falling back to comma-separated parsing."
                        )
                        partition_cols = [
                            col.strip()
                            for col in raw_partitions.split(",")
                            if col.strip()
                        ]
                except json.JSONDecodeError:
                    partition_cols = [
                        col.strip() for col in raw_partitions.split(",") if col.strip()
                    ]

        args_dict["partition_cols"] = partition_cols
        return args_dict
