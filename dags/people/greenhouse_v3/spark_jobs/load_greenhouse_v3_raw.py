import json
import logging
from typing import Any, Dict, List

from pyspark.sql import SparkSession

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.api.auth.oauth2 import BasicAuthOAuth2ClientCredentials
from bietlejuice.base.api.common.client import BaseAPIClient
from bietlejuice.base.api.pagination.header_link import HeaderLinkPaginator
from bietlejuice.base.api.parser.argument_parser import BaseJobArgumentParser
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import insert_partitions, json_to_dataframe
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader

LOGGER = logging.getLogger(__name__)

# Cluster validation: add_validation_target_args / resolve_datalake_write_target
# (--target-database-name, --target-table-name) via BaseJobArgumentParser + RawLayerLoader.


class GreenhouseAPIV3(BaseAPIClient):
    """
    API Client for the Greenhouse Harvest v3 API.
    Handles authentication, pagination, and parameter processing for data ingestion.
    """

    # --- API Configuration Constants ---
    _API_BASE_URL = "https://harvest.greenhouse.io/v3/"
    _TOKEN_URL = "https://auth.greenhouse.io/token"

    # --- Databricks Secrets Configuration Constants ---
    _DATABRICKS_SCOPE = "PEOPLE"
    _DATABRICKS_SECRET_KEY_PREFIX = APIEnum.GREENHOUSE_V3
    _CLIENT_ID_FIELD = "client_id"
    _CLIENT_SECRET_FIELD = "client_secret"

    _V3_API_DATE_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

    def __init__(self, job_args: Dict[str, Any]):
        """Initializes the API client with job-specific arguments."""
        super().__init__(base_url=self._API_BASE_URL)

        self.endpoint = job_args.get("table_name")
        self.params = job_args.get("params", {})
        self.base_filters = self._parse_json_field(job_args.get("base_filters", {}))
        self.load_start_date = job_args.get("load_start_date")
        self.load_end_date = job_args.get("load_end_date")
        self.extraction_type = job_args.get("extraction_type", "full")

        self._apply_authentication()
        self._apply_date_filters()

    @staticmethod
    def _parse_json_field(value):
        """Parses a field that may arrive as a JSON string due to framework serialization."""
        if isinstance(value, str):
            return json.loads(value)
        return value

    def _get_secret_key(self) -> str:
        """Derives the per-table Databricks secret key from the endpoint name."""
        if not self.endpoint:
            raise ValueError("Cannot derive secret key: table_name is not set.")
        return f"{self._DATABRICKS_SECRET_KEY_PREFIX}_{self.endpoint.upper()}"

    def _apply_authentication(self):
        """Configures and applies the authentication handler to the session."""
        auth_handler = BasicAuthOAuth2ClientCredentials(
            databricks_scope=self._DATABRICKS_SCOPE,
            secret_key=self._get_secret_key(),
            token_url=self._TOKEN_URL,
            client_id_field=self._CLIENT_ID_FIELD,
            client_secret_field=self._CLIENT_SECRET_FIELD,
        )
        auth_handler.apply_auth(self.session)
        self.session.headers.update({"Accept": "application/json"})

    def _apply_date_filters(self):
        """Processes ``base_filters`` from the declaration YAML into API query params.

        Each key in ``base_filters`` follows the convention ``{field}_{operator}``
        (e.g. ``updated_at_gte``, ``updated_at_lt``).  Values are placeholders
        (``load_start_date`` / ``load_end_date``) resolved to ISO 8601 timestamps.

        The v3 API accepts multiple operators on the same key as a single
        pipe-separated value, producing e.g.
        ``?updated_at=gte|<start>|lt|<end>``.
        """
        if self.extraction_type != "incremental":
            return
        if not self.base_filters:
            return

        date_placeholders = {
            "load_start_date": self.load_start_date,
            "load_end_date": self.load_end_date,
        }

        grouped: Dict[str, List[str]] = {}
        for key, placeholder in self.base_filters.items():
            date_value = date_placeholders.get(placeholder)
            if date_value is None:
                continue
            parts = key.rsplit("_", 1)
            if len(parts) != 2:
                continue
            field, operator = parts
            date_str = date_value.strftime(self._V3_API_DATE_FORMAT)
            grouped.setdefault(field, []).append(f"{operator}|{date_str}")

        for field, values in grouped.items():
            self.params[field] = "|".join(values)

        LOGGER.info(f"Applied incremental date filters from base_filters: {grouped}")

    def get_all_paginated_results(self) -> List[Dict[str, Any]]:
        """
        Fetches all results from a paginated endpoint.
        """
        if not self.endpoint:
            raise ValueError(
                "API endpoint (table_name) is not defined in the job arguments."
            )

        LOGGER.info(
            f"Starting paginated fetch for endpoint: '{self.endpoint}' with parameters: {self.params}"
        )

        paginator = HeaderLinkPaginator(
            client=self, endpoint=self.endpoint, params=self.params
        )
        # The returned generator yields lists of items (pages), so we need to flatten it.
        return [item for page in paginator.fetch_all() for item in page]


def main():
    """
    Main function to orchestrate the Greenhouse v3 data ingestion job.
    """
    try:
        job_args = BaseJobArgumentParser.parse_args()
        LOGGER.info(
            f"Running Greenhouse v3 job with the following arguments: {job_args}"
        )

        spark_client = SparkClient()
        spark = SparkSession.builder.getOrCreate()

        LOGGER.info(f"Fetching data for table: {job_args.get('table_name')}")
        api_client = GreenhouseAPIV3(job_args)
        api_data_list = api_client.get_all_paginated_results()

        if api_data_list:
            LOGGER.info(
                f"Found {len(api_data_list)} records. Starting Spark processing."
            )
            df = json_to_dataframe(spark, api_data_list)

            date_column_to_partition = job_args.get(
                "date_column_to_partition", "ts_load"
            )
            df = insert_partitions(df, date_column_to_partition)

            raw_loader = RawLayerLoader(
                spark_client=spark_client,
                environment=job_args["environment"],
                source=job_args["dag_name"],
                datalake_bucket=job_args["datalake_bucket"],
                table_name=job_args["table_name"],
                partition_cols=job_args["partition_cols"],
                extraction_type=job_args["extraction_type"],
                target_database_name=job_args.get("target_database_name"),
                target_table_name=job_args.get("target_table_name"),
            )
            raw_loader.load_to_raw(df)
            LOGGER.info(
                f"Data for table '{job_args.get('table_name')}' loaded successfully into the raw layer."
            )
        else:
            LOGGER.warning(
                f"No data returned from the v3 API for table: '{job_args.get('table_name')}'. "
                "No data will be loaded in this execution."
            )

    except Exception as e:
        LOGGER.error(
            f"An unhandled error occurred during the v3 job execution: {e}",
            exc_info=True,
        )
        raise


if __name__ == "__main__":
    main()
