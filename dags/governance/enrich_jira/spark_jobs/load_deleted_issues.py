
import argparse
import json
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db.datalake_metastore_service import DatalakeMetastoreService
from bietlejuice.base.spark import BaseSparkContext, BaseDBUtils
from bietlejuice.loaders.delta_loader import DeltaLoader
from datetime import datetime
from pyspark.sql import DataFrame
from pyspark.sql.types import (
    StructType,
    StructField,
    StringType,
    DateType,
)
from quintoandar_jira_api_client.clients import JiraClient
from quintoandar_logger import QuintoAndarLogger

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_jira_deleted_issues"
logger = QuintoAndarLogger(JOB_NAME)

def main() -> None:
    args = parse_args()
    existing_issues_in_datalake = get_existing_issue_ids_in_datalake(json.loads(args.project_ids))
    deleted_issues_list = get_deleted_issue_ids(existing_issues_in_datalake)
    deleted_issues_df = create_dataframe(deleted_issues_list)
    load_table(
        deleted_issues_df,
        args.environment,
        args.datalake_bucket,
        args.schema,
        args.table_name,
    )

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(JOB_NAME)
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("datalake_bucket", help="bucket value in forno/prod")
    parser.add_argument("schema", help="name of the schema of the table to be saved in the data lake")
    parser.add_argument("table_name", help="name of the table to be saved in the data lake")
    parser.add_argument("project_ids", help="IDs of all the projects to find deleted issues, as a JSON encoded list")
    args = parser.parse_args()

    logger.info(f"m=main,msg='starting job',environment={args.environment},"
                f"datalake_bucket={args.datalake_bucket},schema={args.schema},"
                f"table_name={args.table_name},project_ids={args.project_ids}"
    )

    return args
  
def get_existing_issue_ids_in_datalake(project_keys: list[str]) -> list[str]:
    logger.info("m=get_existing_issue_ids_in_datalake,msg='getting existing issues in datalake'")
    project_key_filter = ",".join([f"'{project_key}'" for project_key in project_keys])
    rows = BaseSparkContext.spark.table("datalake_jira.issues")\
        .filter(f"""
            SPLIT_PART(id_issue, '-', 1) IN ({project_key_filter})
            AND current_status_category != 'Done'
            AND NOT COALESCE(is_deleted, FALSE)
      """)\
        .select("id_issue")\
        .collect()
    return [row.id_issue for row in rows]

def get_deleted_issue_ids(issue_ids: list[str]) -> list[str]:
    logger.info("m=get_deleted_issue_ids,msg='getting deleted issues'")
    client = get_jira_client()
    deleted_issues = []
    for issue_id in issue_ids:
        if client.issue_deleted(issue_id):
            deleted_issues.append(issue_id)
    return deleted_issues

def get_jira_client() -> JiraClient:
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        global dbutils
        dbutils = base_dbutils.get_dbutils()

    json_credentials = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.JIRA)
    credentials = json.loads(json_credentials)
    return JiraClient(username=credentials["username"], token=credentials["token"], server=credentials["server"])

def create_dataframe(deleted_issue_ids: list[str]) -> DataFrame:
    current_date = datetime.now().date()
    return BaseSparkContext.spark.createDataFrame(
        [(issue_id, current_date) for issue_id in deleted_issue_ids],
        schema=StructType(
            [
                StructField("id_issue", StringType(), True),
                StructField("dt_deleted", DateType(), True),
            ]
        )
    )

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

    loader = DeltaLoader()
    loader.load_table(
        table_name=f"{database_name}.{table_name}",
        path=f"{database_location}/{table_name}",
        source_df=dataframe,
        merge_on=["id_issue"],
        when_matched_update_condition="FALSE"
    )

if __name__ == "__main__":
    main()