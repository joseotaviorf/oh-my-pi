import sys
from bietlejuice.clients.db_clients import SparkClient
from quintoandar_logger import QuintoAndarLogger
from pyspark.sql import SparkSession
from bietlejuice.base.spark import BaseDBUtils

from bietlejuice.jobs.degreed.argument_parser import JobArgumentParser
from bietlejuice.jobs.degreed.degreed_api import DegreedAPI
from bietlejuice.jobs.common.raw_layer_loader import RawLayerLoader
from bietlejuice.jobs.common.helpers import json_to_dataframe

LOGGER = QuintoAndarLogger(__name__)

def main():
    """
    Main function to orchestrate the Degreed data ingestion pipeline.
    """

    try:
        job_args = JobArgumentParser.parse_args()
        LOGGER.info(f"Running with the following arguments: {job_args}")

        spark_client = SparkClient()
        spark = SparkSession.builder.getOrCreate() 
        
        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

        api_client = DegreedAPI(job_args)
        api_data_list = api_client.get_all_paginated_results()

        if api_data_list:
            
            df = json_to_dataframe(spark, api_data_list)
            
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
            
        else:
            LOGGER.warning(
                f"No data returned from the API for table: {job_args.get('table_name')}. "
                "No data will be loaded."
            )

    except Exception as e:
        LOGGER.error(f"An unhandled error occurred during the job execution: {e}", exc_info=True)
        raise

if __name__ == "__main__":
    main()
