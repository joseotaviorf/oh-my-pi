import json
import requests
import threading
import concurrent.futures

from argparse import ArgumentParser
from datetime import datetime

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.clients.db_clients import SparkClient


JOB_NAME = "load_reverse_inside_sales_whitelist"


def create_data_payload(item):
    """
    Create the data payload based on the original spark dataframe.
    """
    data = {
        "keyName": key_name,
        "type": api_type,
    }
    data["keyValue"] = item["phone_number"]

    # Create the contextFields dictionary with the desired structure
    context_fields = {
        "id_user_list": item.get("users"),
        "is_tenant_post_contract": item.get("is_tenant_post_contract"),
        "is_landlord_post_contract": item.get("is_landlord_post_contract"),
        "has_published_listings": item.get("has_published_listings"),
        "whitelist_group": item.get("whitelist_group"),
    }

    data["contextFields"] = context_fields
    return data


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    logger = QuintoAndarLogger("MinorityReportAPIClient")

    parser.add_argument("environment")
    parser.add_argument("dag_name")
    parser.add_argument("minority_report_endpoint")
    parser.add_argument("api_type")
    parser.add_argument("key_name")
    parser.add_argument("table_to_send")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    dag_name = args.dag_name
    minority_report_endpoint = args.minority_report_endpoint
    table_to_send = args.table_to_send
    api_type = args.api_type
    key_name = args.key_name
    execution_date = args.execution_date

    spark_client = SparkClient()

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=dag_name, layer=LayerEnum.REVERSE.value, table_name=table_to_send
    )

    # transform the df to json and split it into a list of lists of 100 records
    df = spark_client.conn.sql(query)
    df_list = df.toJSON().map(lambda str_json: json.loads(str_json)).collect()
    batches = [df_list[x : x + 100] for x in range(0, len(df_list), 100)].copy()
    total_batches = len(batches)

    session = requests.Session()
    session.headers.update(
        {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {dbutils.secrets.get(scope='quintoandar', key='MINORITY_REPORT_API')}"
        }
    )

    for idx, batch in enumerate(batches):
        new_batch = [create_data_payload(x) for x in batch]
        resp = session.post(
            minority_report_endpoint,
            data=json.dumps(new_batch),
        )
        if resp.status_code == 200:
            logger.info(f" Succesfully loaded batch {idx + 1}/{len(batches)}")
        else:
            logger.info(resp.raise_for_status())
