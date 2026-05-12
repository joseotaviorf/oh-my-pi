import argparse
import json
import logging
from datetime import datetime
from typing import Any, Dict

LOGGER = logging.getLogger(__name__)


class BaseJobArgumentParser:
    """
    A base class for parsing common command-line arguments for integration jobs.
    Handles standard arguments, dates, partitions, and dynamically processes
    API parameters with date placeholders.
    """

    _description = "API Data Integration Pipeline"

    @classmethod
    def create_parser(cls) -> argparse.ArgumentParser:
        """
        Creates and returns an argument parser with the default job settings.
        """
        parser = argparse.ArgumentParser(description=cls._description)

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

    @staticmethod
    def _process_dynamic_params(
        args_dict: Dict[str, Any], api_date_format: str
    ) -> Dict[str, Any]:
        """
        Processes request parameters by replacing date placeholders with actual
        values from the job arguments, using the specified date format.
        """
        params = args_dict.get("params", {})
        processed_params = params.copy()
        load_start_date = args_dict.get("load_start_date")
        load_end_date = args_dict.get("load_end_date")

        for key, value in processed_params.items():
            if isinstance(value, str):
                if "load_start_date" in value and load_start_date:
                    date_str = load_start_date.strftime(api_date_format)
                    processed_params[key] = value.replace("load_start_date", date_str)

                if "load_end_date" in value and load_end_date:
                    date_str = load_end_date.strftime(api_date_format)
                    processed_params[key] = value.replace("load_end_date", date_str)

        return {k: v for k, v in processed_params.items() if v is not None}

    @classmethod
    def parse_args(cls, api_date_format: str = "%Y-%m-%d") -> dict:
        """
        Parses the command-line arguments into a dictionary and processes
        dynamic API parameters.

        Args:
            api_date_format (str): The specific date format required by the API.

        Returns:
            dict: A dictionary containing the final, processed job arguments.
        """
        parser = cls.create_parser()
        args = parser.parse_args()
        args_dict = vars(args)

        extra_details_str = args_dict.pop("extra_details", "{}")
        try:
            extra_details = json.loads(extra_details_str)
            args_dict.update(extra_details)
        except json.JSONDecodeError as e:
            LOGGER.error(
                f"Invalid JSON for extra_details: '{extra_details_str}'. Error: {e}"
            )
            raise

        # Check if 'params' exists and is a string; if so, parse it.
        if "params" in args_dict and isinstance(args_dict.get("params"), str):
            try:
                args_dict["params"] = json.loads(args_dict["params"])
            except json.JSONDecodeError as e:
                LOGGER.error(
                    f"The 'params' field within extra_details must be a valid JSON object string. "
                    f"Failed to parse: '{args_dict['params']}'. Error: {e}"
                )
                raise

        for date_field in ["load_start_date", "load_end_date", "execution_date"]:
            date_str = args_dict.get(date_field)
            if date_str:
                try:
                    args_dict[date_field] = datetime.strptime(date_str, "%Y-%m-%d")
                except ValueError:
                    try:
                        args_dict[date_field] = datetime.fromisoformat(
                            str(date_str).replace("Z", "+00:00")
                        )
                    except (ValueError, TypeError) as e:
                        LOGGER.error(
                            f"Invalid date format for {date_field}: '{date_str}'. "
                            f"Expected YYYY-MM-DD or ISO-8601. Error: {e}"
                        )
                        raise

        if "params" in args_dict:
            args_dict["params"] = cls._process_dynamic_params(
                args_dict, api_date_format
            )

        raw_partitions = args_dict.get("partitions", "").strip()
        if raw_partitions:
            try:
                parsed = json.loads(raw_partitions)
                if isinstance(parsed, list) and all(isinstance(p, str) for p in parsed):
                    partition_cols = [col.strip() for col in parsed if col.strip()]
                else:
                    partition_cols = [
                        col.strip() for col in raw_partitions.split(",") if col.strip()
                    ]
            except json.JSONDecodeError:
                partition_cols = [
                    col.strip() for col in raw_partitions.split(",") if col.strip()
                ]
        else:
            partition_cols = []

        args_dict["partition_cols"] = partition_cols
        return args_dict
