import json
import logging
import requests
from argparse import ArgumentParser

from bietlejuice.clients.db_clients import SparkClient
from quintoandar_logger import QuintoAndarLogger


def _post_minority_data(idx, batch):
    try:
        new_batch = [_create_data_payload(item) for item in batch]

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


def _create_data_payload(item):
    data = {"keyName": key_name, "type": api_type}
    data["keyValue"] = item.get(key_value)
    data["contextFields"] = _create_context_fields_json(item)
    return data


def _create_context_fields_json(item):
    context_fields_json = {}
    for context_field in context_fields:
        field_value = context_field.get("value")
        context_fields_json[context_field.get("name")] = item.get(field_value)
    return context_fields_json


JOB_NAME = "load_reverse_inspections"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("environment")
    parser.add_argument("dag_name")
    parser.add_argument("minority_report_endpoint")
    parser.add_argument("minority_request_header")
    parser.add_argument("table_to_send")
    parser.add_argument("table_details")
    parser.add_argument("query_model")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    dag_name = args.dag_name
    minority_report_endpoint = args.minority_report_endpoint
    minority_request_header = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {dbutils.secrets.get(scope='quintoandar', key='MINORITY_REPORT_API')}"
    }
    table_to_send = args.table_to_send
    query = args.query_model
    execution_date = args.execution_date

    table_details = json.loads(args.table_details)

    api_type = table_details.get("type")
    key_name = table_details.get("key_name")
    key_value = table_details.get("key_value")
    context_fields = table_details.get("context_fields")

    data_source_table = table_details.get("data_source_table")
    filter_date_column = table_details.get("filter_date_column")
    selected_columns = table_details.get("selected_columns", "*")
    query = query.format(
        selected_columns=selected_columns,
        data_source_table=data_source_table,
        filter_date_column=filter_date_column,
        filter_date_value=execution_date,
    )

    logger.info(
        f"""m={JOB_NAME}, environment={environment}, source={dag_name},
        minority_report_endpoint={minority_report_endpoint},
        execution_date={execution_date}, reverse_tag={api_type},
        table_to_send={table_to_send}"""
        "msg=Starting spark job..."
    )

    spark_client = SparkClient()

    df = spark_client.conn.sql(query)
    df_list = df.toJSON().map(lambda str_json: json.loads(str_json)).collect()
    batches = [df_list[x : x + 100] for x in range(0, len(df_list), 100)].copy()
    total_batches = len(batches)

    session = requests.Session()
    session.headers.update(minority_request_header)

    [_post_minority_data(idx, bath) for idx, bath in enumerate(batches)]
