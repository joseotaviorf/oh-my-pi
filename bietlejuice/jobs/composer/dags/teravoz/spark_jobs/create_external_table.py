import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import AthenaClient
from bietlejuice.jobs.composer.etl.transformer.teravoz import TeravozTransformer
from bietlejuice.jobs.composer.services.metastore_services import AthenaMetastoreService
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService

DATABRICKS_SCOPE = "quintoandar"

JOB_NAME = "create_external_table"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="create_external_table")

    # args passed by Airflow task
    parser.add_argument(
        "table_name", type=str, help="which endpoint to call and table name"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket")
    parser.add_argument("athena_query_result_location")

    args = parser.parse_args()

    logger.info(
        "m=create_external_table, table_name={}, execution_date={}, "
        "environment={}, msg=print args spark jobs params".format(
            args.table_name, args.execution_date, args.environment
        )
    )

    datalake_layer = "clean"
    execution_date = args.execution_date
    table_name = args.table_name.replace("-", "_")
    environment = args.environment
    bucket = args.datalake_bucket
    datalake_bucket = args.datalake_bucket
    athena_query_result_location = args.athena_query_result_location

    db_info = DatalakeMetastoreService.get_db_info(
        environment, "teravoz", datalake_bucket
    )

    athena_metastore_service = AthenaMetastoreService(
        AthenaClient(athena_query_result_location)
    )
    athena_metastore_service.create_database(db_info["db_clean_athena"])

    # create external table and add partition
    transformer = TeravozTransformer(environment, bucket, athena_metastore_service)

    transformer.create_athena_table(
        datalake_layer=datalake_layer, table_name=table_name
    )

    transformer.add_partition(
        datalake_layer=datalake_layer,
        table_name=table_name,
        execution_date=execution_date,
    )
