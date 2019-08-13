import json
import logging
from argparse import ArgumentParser

from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.loaders.teravoz.factory import TeravozFactory

from quintoandar_logger import QuintoAndarLogger

DATABRICKS_SCOPE = "quintoandar"


JOB_NAME = "load_teravoz_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


@logger
def exec_factory_method(
    endpoint, method, api_user, api_pwd, environment, execution_date
):

    teravoz = TeravozFactory.factory(
        entity=endpoint,
        api_user=api_user,
        api_pwd=api_pwd,
        environment=environment,
        execution_date=execution_date,
    )

    getattr(teravoz, method)
    return teravoz


if __name__ == "__main__":

    parser = ArgumentParser(description="load_teravoz_to_datalake_raw")

    # args passed by Airflow task
    parser.add_argument("endpoint", type=str, help="which endpoint to call")
    parser.add_argument(
        "datalake_layer", type=str, help="which layer from datalake to load"
    )
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("environment", type=str, help="5a-datalake-(forno/prod) values")

    args = parser.parse_args()

    logger.info(
        "m=load_teravoz_into_datalake, endpoint={}, datalake_layer={}, execution_date={}, msg=print args spark jobs params".format(
            args.endpoint, args.datalake_layer, args.execution_date
        )
    )

    datalake_layer = args.datalake_layer
    execution_date = args.execution_date
    endpoint = args.endpoint
    environment = args.environment

    # start Spark Session
    base_dbutils = BaseDBUtils()

    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    # get Teravoz credentials stored in Databricks secrets
    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="ENV_TERAVOZ")

    credentials = json.loads(json_credentials)

    teravoz = exec_factory_method(
        endpoint=endpoint,
        method="__init__",
        api_user=credentials["teravoz_user"],
        api_pwd=credentials["teravoz_password"],
        environment=environment,
        execution_date=execution_date,
    )

    df = teravoz.request_api_and_get_dataframe()
    teravoz.load_data_into_datalake(df=df, datalake_layer=datalake_layer)
