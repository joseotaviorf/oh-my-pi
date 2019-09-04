import logging
from argparse import ArgumentParser

from bietlejuice.jobs.composer.loaders.teravoz import TeravozLoader
from bietlejuice.jobs.composer.etl.transformer.teravoz import TeravozTransformer

from quintoandar_logger import QuintoAndarLogger

DATABRICKS_SCOPE = "quintoandar"


JOB_NAME = "load_data_to_clean"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":

    parser = ArgumentParser(description="load_teravoz_into_datalake")

    # args passed by Airflow task
    parser.add_argument("file_name", type=str, help="file name is equal table name")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()

    logger.info(
        "m=load_data_to_clean, file_name={}, execution_date={}, msg=print args spark jobs params".format(
            args.file_name, args.execution_date
        )
    )

    execution_date = args.execution_date
    table_name = file_name = args.file_name.replace("-", "_")
    environment = args.environment

    # execute query and get dataframe
    teravoz_transformer = TeravozTransformer(env=environment)
    df = teravoz_transformer.create_dataframe_from_datalake_sql_file(
        file_name=file_name, execution_date=execution_date
    )

    # load dataframe into datalake
    teravoz_loader = TeravozLoader(
        environment=environment,
        datalake_layer="clean",
        table_name=table_name,
        execution_date=execution_date,
    )
    teravoz_loader.load_data_into_datalake(df)
