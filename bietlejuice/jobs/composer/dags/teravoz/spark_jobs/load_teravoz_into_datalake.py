import json
import logging
from argparse import ArgumentParser

from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.loaders.teravoz.factory import TeravozFactory

from quintoandar_logger import QuintoAndarLogger

DATABRICKS_SCOPE = "quintoandar-prod"
# NB_THREADS = 4


JOB_NAME = "load_teravoz_into_datalake"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def exec_factory_method(endpoint, method, api_user, api_pwd, execution_date):

    teravoz = TeravozFactory.factory(
        entity=endpoint,
        api_user=api_user,
        api_pwd=api_pwd,
        execution_date=execution_date,
    )

    getattr(teravoz, method)
    return teravoz


if __name__ == "__main__":

    parser = ArgumentParser(description="load_teravoz_to_datalake_raw")

    # args passed by Airflow task
    parser.add_argument("endpoint", type=str, help="which endpoint to call")
    parser.add_argument("datalake_layer", type=str, help="which endpoint to call")
    parser.add_argument("execution_date", type=str, help="which endpoint to call")

    args = parser.parse_args()

    datalake_layer = args.datalake_layer
    execution_date = args.execution_date
    endpoint = args.endpoint

    if datalake_layer == "raw":

        # start Spark Session
        base_dbutils = BaseDBUtils()

        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        # get Teravoz credentials stored in Databricks secrets
        json_credentials = dbutils.secrets.get(
            scope=DATABRICKS_SCOPE, key="ENV_TERAVOZ"
        )

        credentials = json.loads(json_credentials)

        teravoz = exec_factory_method(
            endpoint=endpoint,
            method="__init__",
            api_user=credentials["teravoz_user"],
            api_pwd=credentials["teravoz_password"],
            execution_date=execution_date,
        )

        df = teravoz.request_api_and_get_dataframe()
        teravoz.load_data_into_datalake(df=df, datalake_layer=datalake_layer)
