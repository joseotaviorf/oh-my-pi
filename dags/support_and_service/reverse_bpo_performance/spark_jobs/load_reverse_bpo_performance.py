import json
import requests
import logging
from argparse import ArgumentParser
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.pipeline.layer_enum import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.clients.db_clients import SparkClient


JOB_NAME = "load_reverse_bpo_performance"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def _post_minority_data(idx, batch, key_name, api_type):
    try:
        new_batch = [_create_data_payload(item, key_name, api_type) for item in batch]

        response = session.post(minority_report_endpoint, data=json.dumps(new_batch))
        response.raise_for_status()

        print(f" Succesfully loaded batch {idx + 1}/{len(batches)}")

    except requests.exceptions.RequestException as e:
        if e.response.status_code == 400:
            logger.error(
                f"m=_post_minority_data, response={e.response.content}, status_code={e.response.status_code}, "
                "msg=Invalid batch size."
            )
        else:
            raise Exception(
                f"m=_post_minority_data, response={e.response.content}, status_code={e.response.status_code}, "
                "msg=an exception occurred"
            )

def _create_data_payload(item, key_name, api_type):
    """
    Create the data payload based on the original spark dataframe.
    """
    data = {
        "keyName": key_name,
        "type": api_type,
    }
    data["keyValue"] = item.get("key_csat")

    # Create the contextFields dictionary with the desired structure
    context_fields = {
        "csatKey": item.get("key_csat"),
        "reference_date": item.get("reference_date"),
        "bpo_name": item.get("bpo_name"),
        "channel_type": item.get("channel_type"),
        "department": item.get("department"),
        "csat_rate_7_day": item.get("csat_rate_7_day"),
        "csat_rate_30_day": item.get("csat_rate_30_day"),
        "resolution_rate_7_day": item.get("resolution_rate_7_day"),
        "resolution_rate_30_day": item.get("resolution_rate_30_day"),
    }

    data["contextFields"] = context_fields
    return data


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    logger = QuintoAndarLogger("MinorityReportAPIClient")

    parser.add_argument("environment")
    parser.add_argument("dag_name")
    parser.add_argument("minority_report_endpoint")
    parser.add_argument("table")
    parser.add_argument("table_details")
    parser.add_argument("key_name")
    parser.add_argument("type")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    dag_name = args.dag_name
    minority_report_endpoint = args.minority_report_endpoint
    minority_request_header = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {dbutils.secrets.get(scope='quintoandar', key='MINORITY_REPORT_API')}"
    }
    table = args.table
    table_details = args.table_details
    api_type = args.type
    key_name = args.key_name
    execution_date = args.execution_date

    spark_client = SparkClient()

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=dag_name, layer=LayerEnum.REVERSE.value, table_name=table
    )
    df = spark_client.conn.sql(query)

    # transform the df to json and split it into a list of lists of 100 records
    df_list = df.toJSON().map(lambda str_json: json.loads(str_json)).collect()
    batches = [df_list[x : x + 100] for x in range(0, len(df_list), 100)].copy()

    session = requests.Session()
    session.headers.update(minority_request_header)
    [_post_minority_data(idx, batch, key_name, api_type) for idx, batch in enumerate(batches)]
