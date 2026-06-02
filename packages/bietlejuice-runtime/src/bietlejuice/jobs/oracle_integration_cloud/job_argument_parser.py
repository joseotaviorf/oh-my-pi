import argparse
import json
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import add_validation_target_args

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
        parser = argparse.ArgumentParser(description="HCM Integration Pipeline")

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
        parser.add_argument("extra_details", help="Extra details (JSON string)")

        add_validation_target_args(parser)

        return parser

    @classmethod
    def parse_args(cls) -> dict:
        """
        Parses command-line arguments into a dictionary.

        Returns:
            dict: A dictionary containing the parsed command-line arguments.
                Includes individual arguments and any key-value pairs from the 'extra_details' JSON string.
                Date strings ('load_start_date', 'load_end_date', 'execution_date') are converted to datetime.date objects.
                The 'partitions' string is parsed into a list of partition columns under the key 'partition_cols'.

        Raises:
            json.JSONDecodeError: If the 'extra_details' argument is not a valid JSON string.
            ValueError: If any of the date arguments are not in the 'YYYY-MM-DD' format,
                        or if the 'partitions' argument is a valid JSON but not a list of strings.
        """
        parser = cls.create_parser()
        args = parser.parse_args()
        args_dict = vars(args)

        extra_details_str = args_dict.pop("extra_details", "{}")
        try:
            extra_details = json.loads(extra_details_str)
        except json.JSONDecodeError as e:
            LOGGER.error(
                f"Invalid JSON for extra_details: {extra_details_str}. Error: {e}",
                exc_info=True,
            )
            raise

        args_dict.update(extra_details)

        for date_field in ["load_start_date", "load_end_date", "execution_date"]:
            if args_dict.get(date_field):
                try:
                    args_dict[date_field] = datetime.strptime(
                        args_dict[date_field], "%Y-%m-%d"
                    ).date()
                except ValueError as e:
                    LOGGER.error(
                        f"Invalid date format for {date_field}: {args_dict[date_field]}. Error: {e}",
                        exc_info=True,
                    )
                    raise

        raw_partitions = args_dict.get("partitions", "").strip()
        partition_cols = []

        if (
            raw_partitions
            and raw_partitions.startswith("[")
            and raw_partitions.endswith("]")
        ):
            try:
                parsed = json.loads(raw_partitions)
                if isinstance(parsed, list) and all(isinstance(p, str) for p in parsed):
                    partition_cols = [p.strip() for p in parsed if p.strip()]
                else:
                    raise ValueError(
                        f"Partitions argument is not a valid JSON list of strings: {raw_partitions}"
                    )
            except json.JSONDecodeError:
                LOGGER.warning(
                    f"Could not parse partitions as JSON, falling back to comma-separated: {raw_partitions}"
                )
                partition_cols = [
                    p.strip() for p in raw_partitions.split(",") if p.strip()
                ]
        elif raw_partitions:
            partition_cols = [p.strip() for p in raw_partitions.split(",") if p.strip()]

        args_dict["partition_cols"] = partition_cols

        return args_dict
