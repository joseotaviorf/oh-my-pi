import logging
from typing import List, Dict, Any

from pyspark.sql import SparkSession

from bietlejuice.clients.db_clients import SparkClient
from base.api.common.client import BaseAPIClient
from bietlejuice.base.api.parser.argument_parser import BaseJobArgumentParser
from bietlejuice.base.api.auth.oauth2 import BasicAuthOAuth2ClientCredentials
from bietlejuice.jobs.common.helpers import json_to_dataframe, insert_partitions
from bietlejuice.base.api.pagination.header_link import HeaderLinkPaginator
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader
from bietlejuice.base.api.api_enum import APIEnum

LOGGER = logging.getLogger(__name__)


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
    _DATABRICKS_SECRET_KEY = APIEnum.GREENHOUSE_V3
    _CLIENT_ID_FIELD = "client_id"
    _CLIENT_SECRET_FIELD = "client_secret"

    def __init__(self, job_args: Dict[str, Any]):
        """Initializes the API client with job-specific arguments."""
        super().__init__(base_url=self._API_BASE_URL)

        self.endpoint = job_args.get("table_name")
        self.params = job_args.get("params", {})
        self.load_start_date = job_args.get("load_start_date")
        self.load_end_date = job_args.get("load_end_date")

        self._apply_authentication()

    def _apply_authentication(self):
        """Configures and applies the authentication handler to the session."""
        auth_handler = BasicAuthOAuth2ClientCredentials(
            databricks_scope=self._DATABRICKS_SCOPE,
            secret_key=self._DATABRICKS_SECRET_KEY,
            token_url=self._TOKEN_URL,
            client_id_field=self._CLIENT_ID_FIELD,
            client_secret_field=self._CLIENT_SECRET_FIELD,
        )
        auth_handler.apply_auth(self.session)
        self.session.headers.update({"Accept": "application/json"})


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

        paginator = HeaderLinkPaginator(client=self, endpoint=self.endpoint, params=self.params)
        # The returned generator yields lists of items (pages), so we need to flatten it.
        return [item for page in paginator.fetch_all() for item in page]


def main():
    """
    Main function to orchestrate the Greenhouse v3 data ingestion job.
    """
    try:
        job_args = BaseJobArgumentParser.parse_args()
        LOGGER.info(f"Running Greenhouse v3 job with the following arguments: {job_args}")

        spark_client = SparkClient()
        spark = SparkSession.builder.getOrCreate()

        LOGGER.info(f"Fetching data for table: {job_args.get('table_name')}")
        api_client = GreenhouseAPIV3(job_args)
        api_data_list = api_client.get_all_paginated_results()

        if api_data_list:
            LOGGER.info(f"Found {len(api_data_list)} records. Starting Spark processing.")
            df = json_to_dataframe(spark, api_data_list)

            date_column_to_partition = job_args.get("date_column_to_partition", "ts_load")
            df = insert_partitions(df, date_column_to_partition)

            raw_loader = RawLayerLoader(
                spark_client=spark_client,
                environment=job_args["environment"],
                source=job_args["dag_name"],
                datalake_bucket=job_args["datalake_bucket"],
                table_name=job_args["table_name"],
                partition_cols=job_args["partition_cols"],
                extraction_type=job_args["extraction_type"]
            )
            raw_loader.load_to_raw(df)
            LOGGER.info(f"Data for table '{job_args.get('table_name')}' loaded successfully into the raw layer.")
        else:
            LOGGER.warning(
                f"No data returned from the v3 API for table: '{job_args.get('table_name')}'. "
                "No data will be loaded in this execution."
            )

    except Exception as e:
        LOGGER.error(f"An unhandled error occurred during the v3 job execution: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    main()