import json
import logging
from argparse import ArgumentParser

from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.consumers.teravoz import TeravozFactoryConsumer

from quintoandar_logger import QuintoAndarLogger

DATABRICKS_SCOPE = "quintoandar"


JOB_NAME = "load_teravoz_into_datalake_raw"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


@logger
def exec_factory_method(endpoint, method, api_user, api_pwd, execution_date):

    teravoz_consumer = TeravozFactoryConsumer.factory(
        endpoint=endpoint,
        api_user=api_user,
        api_pwd=api_pwd,
        execution_date=execution_date,
    )

    getattr(teravoz_consumer, method)
    return teravoz_consumer


if __name__ == "__main__":

    parser = ArgumentParser(description="load_teravoz_into_datalake")

    # args passed by Airflow task
    parser.add_argument(
        "endpoint_name", type=str, help="which endpoint to call and table name"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="forno/prod values")

    args = parser.parse_args()

    logger.info(
        "m=load_teravoz_into_datalake_raw, endpoint_name={}, datalake_layer={}, execution_date={}, msg=print args spark jobs params".format(
            args.endpoint_name, args.datalake_layer, args.execution_date
        )
    )

    execution_date = args.execution_date
    endpoint_name = args.endpoint_name
    environment = args.environment

    # start Spark Session
    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # get Teravoz credentials stored in Databricks secrets
    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="teravoz")

    credentials = json.loads(json_credentials)

    teravoz_consumer = exec_factory_method(
        endpoint=endpoint_name,
        method="__init__",
        api_user=credentials["teravoz_user"],
        api_pwd=credentials["teravoz_password"],
        execution_date=execution_date,
    )
    df = teravoz_consumer.request_api_and_get_dataframe(endpoint_name)
