from argparse import ArgumentParser
import logging

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.etl.transformer.teravoz import TeravozTransformer


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
    parser.add_argument(
        "datalake_layer", type=str, help="which layer from datalake to load"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")
    parser.add_argument(
        "has_partitions", type=str, help="if table will have partitions"
    )  # temp

    args = parser.parse_args()

    logger.info(
        "m=load_teravoz_into_datalake, table_name={}, datalake_layer={}, execution_date={}, msg=print args spark jobs params".format(
            args.table_name, args.datalake_layer, args.execution_date
        )
    )

    datalake_layer = args.datalake_layer
    execution_date = args.execution_date
    table_name = args.table_name.replace("-","_")
    environment = args.environment
    has_partitions = True if args.has_partitions == "True" else False

    # create external table and add partition
    transformer = TeravozTransformer(environment)

    transformer.create_athena_table(
        datalake_layer=datalake_layer,
        table_name=table_name,
        has_partitions=has_partitions,
    )

    if has_partitions:
        transformer.add_partition(
            datalake_layer=datalake_layer,
            table_name=table_name,
            execution_date=execution_date,
        )
