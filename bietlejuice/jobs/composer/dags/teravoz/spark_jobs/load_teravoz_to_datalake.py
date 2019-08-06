import json
import math
from datetime import datetime
from multiprocessing.dummy import Pool
# from bietlejuice.jobs.composer.base import BaseDBUtils



DATABRICKS_SCOPE = "quintoandar-prod"
NB_THREADS = len(ENDPOINTS.keys())

if __name__ == "__main__":
    
    # start Spark Session
    base_dbutils = BaseDBUtils()
    
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()
    
    # get Teravoz credentials stored in Databricks secrets
    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key="ENV_TERAVOZ")
    credentials = json.loads(json_credentials)
    
    teravoz_client = TeravozLoader(api_user = credentials["teravoz_user"], 
                                   api_pwd = credentials["teravoz_password"])
    
    
    # endpoints_file = open('api_requests.py', 'r')
    # endpoints = endpoints_file.format(execution_date=datetime.datetime(2019, 7, 1))
    with Pool(NB_THREADS) as p:
        p.map (
            teravoz_client.load_data_into_datalake,
            [
                (edp, param)
                for edp, param in ENDPOINTS.items()
            ],
        )
