import argparse
import requests
import json
from base64 import b64encode
from databricks.sdk import WorkspaceClient
from pyspark.sql.functions import current_timestamp, lit
from pyspark.sql.dataframe import DataFrame
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services import ConfigurationService
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_instance_pools"
COLUMNS = {
    "instance_pool_id": "id_instance_pool",
    "node_type_id": "id_node_type",
    "instance_pool_name": "instance_pool_name",
    "aws_attributes": "aws_attributes",
    "default_tags": "default_tags",
    "idle_instance_autotermination_minutes": "idle_instance_autotermination_minutes",
    "state": "state",
    "custom_tags": "custom_tags",
    "max_capacity": "max_capacity",
    "min_idle_instances": "min_idle_instances",
    "preloaded_spark_versions": "preloaded_spark_versions",
    "enable_elastic_disk": "is_elastic_disk_enabled",
}

logger = QuintoAndarLogger(JOB_NAME)

def main() -> None:
    args = parse_args()
    df_instance_pools = find_instance_pools(args.dag_name)
    load_table(df_instance_pools, args.env, args.bucket, args.database_base_name, args.table_name)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("bucket", type=str, help="bucket name")
    parser.add_argument(
        "dag_name",
        type=str,
        help="name of the Airflow DAG, without the bietlejuice prefix",
    )
    parser.add_argument(
        "database_base_name",
        type=str,
        help="base name for database, e.g. 'source' for raw/clean layer and 'source' and/or 'context' for enrich layer",
    )
    parser.add_argument("table_name", type=str, help="table name that will be created")
    return parser.parse_args()


def find_instance_pools(dag_name: str) -> DataFrame:
    configuration_service = ConfigurationService(dag_name)
    account_id = configuration_service.get_config("account_id")
    workspaces = configuration_service.get_config("workspaces")

    df = None
    for workspace_id, workspace_url in workspaces.items():
        df_workspace = find_instance_pools_in_workspace(account_id, workspace_id, workspace_url)
        if df is None:
            df = df_workspace
        else:
            df = df.unionByName(df_workspace, allowMissingColumns=True)
    return df
  

def find_instance_pools_in_workspace(account_id: str, workspace_id: str, workspace_url: str) -> DataFrame:
    logger.info(f"m=find_instance_pools,msg='finding instance pools in workspace {workspace_url}'")
    workspace_client = WorkspaceClient(
        host=workspace_url,
        token=get_databricks_token(account_id)
    )
    pools = workspace_client.instance_pools.list()
    dict_pools = [
        {COLUMNS[k]: v for k, v in pool.as_dict().items() if k in COLUMNS}
        for pool in pools
    ]
    print(dict_pools)
    df = spark.createDataFrame(dict_pools)
    return df.withColumns({
        "id_workspace": lit(workspace_id),
        "ts_load": current_timestamp()
    })


def get_databricks_token(account_id: str) -> str:
    """get databricks token for a service principal"""
    
    credentials = json.loads(dbutils.secrets.get(scope="data-ingestion", key="data-ingestion-5a"))
    client_id = credentials["client_id"]
    client_secret = credentials["secret"]

    headers = {
        "Content-Type": "application/x-www-form-urlencoded",
        "Authorization": "Basic " + b64encode(f"{client_id}:{client_secret}".encode()).decode()
    }
    payload = {
        "grant_type": "client_credentials",
        "scope": "all-apis"
    }
    url_endpoint = f"https://accounts.cloud.databricks.com/oidc/accounts/{account_id}/v1/token"
    response = requests.post(url_endpoint, headers = headers, data = payload)
    response_data = json.loads(response.text) 
    if "access_token" in response_data:
        return response_data["access_token"]
    else:
        raise Exception(f"Failed to create access token: {response.text}")


def load_table(
    dataframe: DataFrame,
    environment: str,
    datalake_bucket: str,
    schema: str,
    table_name: str,
) -> None:
    logger.info("m=load_table,msg='loading table'")

    db_info = DatalakeMetastoreService.get_db_info(environment, schema, datalake_bucket)
    database_name = db_info["db_enrich_databricks"]
    database_location = db_info["db_enrich_path"]

    loader = DeltaLoader(spark)
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}/{table_name}",
        source_df=dataframe,
    )


if __name__ == "__main__":
    main()