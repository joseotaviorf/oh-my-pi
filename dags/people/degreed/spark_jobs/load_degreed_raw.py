from pyspark.sql import SparkSession
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.jobs.common.helpers import json_to_dataframe
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader
from bietlejuice.jobs.degreed.argument_parser import JobArgumentParser
from bietlejuice.jobs.degreed.degreed_api import DegreedAPI

LOGGER = QuintoAndarLogger(__name__)

# Cluster validation: add_validation_target_args / resolve_datalake_write_target
# (--target-database-name, --target-table-name) via JobArgumentParser + RawLayerLoader.

SCOPE_KEY = "scope"


def main():
    """
    Main function to orchestrate the Degreed data ingestion pipeline.
    """
    try:
        job_args = JobArgumentParser.parse_args()
        LOGGER.info(f"Running with the following arguments: {job_args}")

        if not job_args.get(SCOPE_KEY):
            raise ValueError(
                "Job requires 'scope' in extra_details (e.g. pathways:read, users:read)."
            )

        use_from_id_list = bool(job_args.get("use_ingestion_from_id_list"))

        spark = SparkSession.builder.getOrCreate()
        spark_client = SparkClient()
        BaseDBUtils().get_dbutils()

        api_data_list = _fetch_api_data(job_args, spark, use_from_id_list)

        if api_data_list:
            _load_to_raw(spark, spark_client, job_args, api_data_list)
            LOGGER.info(
                f"Loaded {len(api_data_list)} records into raw table "
                f"{job_args['table_name']}"
            )
        else:
            LOGGER.warning("No data returned from the API. No data will be loaded.")

    except Exception as e:
        LOGGER.error(
            f"An unhandled error occurred during the job execution: {e}", exc_info=True
        )
        raise


def _fetch_api_data(
    job_args: dict, spark: SparkSession, use_from_id_list: bool
) -> list:
    """
    Fetch data from the Degreed API. Uses by-ID ingestion or paginated ingestion
    depending on use_from_id_list.
    """
    if use_from_id_list:
        return _fetch_api_data_from_id_list(job_args, spark)
    return _fetch_api_data_paginated(job_args)


def _fetch_api_data_from_id_list(job_args: dict, spark: SparkSession) -> list:
    api_client = DegreedAPI(job_args)
    return api_client.get_all_from_id_list(spark, job_args)


def _fetch_api_data_paginated(job_args: dict) -> list:
    api_client = DegreedAPI(job_args)
    return api_client.get_all_paginated_results()


def _load_to_raw(
    spark: SparkSession, spark_client: SparkClient, job_args: dict, api_data_list: list
) -> None:
    df = json_to_dataframe(spark, api_data_list)
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


if __name__ == "__main__":
    main()
