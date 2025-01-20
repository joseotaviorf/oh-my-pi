from argparse import ArgumentParser
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils
import json
import logging
import requests
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.services import ConfigurationService
from bietlejuice.services.messaging_services.gchat_service import GChatService
from datetime import datetime

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_into_robbyson_api"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def create_results_payload(results_table_path: str, agent_table_path: str, key_join_tables_fact: str, key_join_tables_dim: str, analyst_key_column: str, start_date: str, end_date: str, context: str) -> list:
    indicators_df = spark.sql(f"SELECT * FROM datalake_static_files_ss.robbyson_indicators WHERE context = '{context}'")
    indicators_content = {row['id_indicator']: row['attributes'] for row in indicators_df.collect()}

    results_df = spark.sql(f"""
        SELECT
            fact.*,
            dim.{analyst_key_column},
            STRING(MAKE_DATE(year, month, day)) AS date
        FROM
            {results_table_path} AS fact
            LEFT JOIN {agent_table_path} AS dim
                ON fact.{key_join_tables_fact} = dim.{key_join_tables_dim}
        WHERE
            MAKE_DATE(year, month, day) BETWEEN DATE('{start_date}') - INTERVAL 30 DAY AND DATE('{end_date}')
    """)

    results_list = []

    for key, value in indicators_content.items():
        columns_used, = value.values()

        for row in results_df.collect():
            results_json = {
                "collaboratorIdentification": row[analyst_key_column],
                "indicadorId": int(key),
                "resultado": 0,
                "date": row['date'],
                "factors": [row[column] for column in columns_used if row[column] is not None]
            }
            results_list.append(results_json)
    return results_list

def parse_arguments() -> dict:
    """
    Parse the arguments passed to the job.
    Returns a dict with the api_url, endpoint, execution date and configurations.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument(
        "start_date", help="Date of the execution in the format YYYY-MM-DD"
    )
    parser.add_argument(
        "end_date", help="End date of the execution in the format YYYY-MM-DD"
    )
    parser.add_argument("dispatch_limits", help="Dispatch limits")
    parser.add_argument("endpoint", help="Api endpoint, where we will send the data")
    parser.add_argument("context", help="Line responsible for processing")
    parser.add_argument("results_table_path")
    parser.add_argument("agent_table_path")
    parser.add_argument("key_join_tables_fact")
    parser.add_argument("key_join_tables_dim")
    parser.add_argument("analyst_key_column")

    args = parser.parse_args()

    dag_name = args.dag_name
    environment = args.environment
    context = args.context
    start_date = args.start_date
    end_date = args.end_date
    endpoint = args.endpoint
    dispatch_limits = args.dispatch_limits
    results_table_path = args.results_table_path
    agent_table_path = args.agent_table_path
    key_join_tables_fact = args.key_join_tables_fact
    key_join_tables_dim = args.key_join_tables_dim
    analyst_key_column = args.analyst_key_column

    return {
        "dag_name": dag_name,
        "environment": environment,
        "context": context,
        "start_date": start_date,
        "end_date": end_date,
        "endpoint": endpoint,
        "dispatch_limits": dispatch_limits,
        "results_table_path": results_table_path,
        "agent_table_path": agent_table_path,
        "key_join_tables_fact": key_join_tables_fact,
        "key_join_tables_dim": key_join_tables_dim,
        "analyst_key_column": analyst_key_column
    }

def send_payload_in_batches(api_url: str, endpoint: str, transaction_id: str, headers: dict, payload: list, batch_size: int):
    """
    Envia o payload em lotes para a API usando o mesmo transaction_id.
    """
    total = len(payload)
    for i in range(0, total, batch_size):
        batch = payload[i:i + batch_size]
        response = requests.post(
            f'{api_url}/{endpoint}/?transaction_id={transaction_id}',
            headers=headers,
            json=batch
        )
        if response.status_code != 200:
            logger.error(f"m=Error sending batch. Batch_index={i // batch_size}, status_code={response.status_code}, response={response.content}")
        else:
            logger.info(f"m=Batch sent successfully. Batch_index={i // batch_size}, size={len(batch)}")

def send_alert_message(error_message: str, dag_name: str, environment: str):
    """
    Envia uma mensagem de alerta no canal configurado com o erro ocorrido.
    """
    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    DAG_NAME = dag_name
    config_service = ConfigurationService(DAG_NAME)
    webhook_key = config_service.get_config("notification_webhooks_keys")["data_quality"]
    gchat_webhook = dbutils.secrets.get(scope="quintoandar", key=webhook_key)

    message_content = (
        f"⚠️\n"
        f"Validation: Payload sending on `{dag_name}`\n"
        f"Environment: *{environment}*\n"
        f"Status: *FAILED*\n"
        f"*Existence validation failed for `{datetime.now().strftime('%Y-%m-%d')}`\n"
    )
    logger.info(f"m=send_alert_message, message=sending gchat message: {message_content}")
    message = Message(content=message_content, destination=gchat_webhook)
    GChatService.send_message(message)

def safe_post_request_with_alert(url: str, headers: dict, json_data=None):
    try:
        response = requests.post(url, headers=headers, json=json_data)
        response.raise_for_status()
        return response
    except requests.exceptions.RequestException as e:
        error_message = f"URL: {url}\nErro: {e}"
        logger.error(f"m=Error during POST request., {error_message}")
        send_alert_message(error_message, job_arguments_dict["dag_name"], job_arguments_dict["environment"])
        return None

def main():
    job_arguments_dict = parse_arguments()

    base_dbutils = BaseDBUtils()
    global dbutils
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    token = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.ROBBYSON)

    config_service = ConfigurationService(job_arguments_dict["dag_name"])
    api_url = config_service.get_config("api_url")

    headers = {
        "token": token,
        "accept": "application/json",
    }

    transaction_response = safe_post_request_with_alert(f'{api_url}/transactions/', headers=headers)
    if transaction_response:
        try:
            transaction_json = json.loads(transaction_response.content.decode('utf-8'))
            transaction_id = transaction_json['data']['_id']
            logger.info(f"m=Success in getting the credentials., transaction_id={transaction_id}")
        except json.JSONDecodeError as e:
            logger.error(f"m=Error decoding transaction response., error={e}")
            raise SystemExit("Transaction setup failed.")
    else:
        raise SystemExit("Transaction setup failed due to request error.")

    logger.info(
        f"m=Success in getting the credentials., transaction_id={transaction_id}"
    )

    results_payload = create_results_payload(
        job_arguments_dict["results_table_path"],
        job_arguments_dict["agent_table_path"],
        job_arguments_dict["key_join_tables_fact"],
        job_arguments_dict["key_join_tables_dim"],
        job_arguments_dict["analyst_key_column"],
        job_arguments_dict["start_date"],
        job_arguments_dict["end_date"],
        job_arguments_dict["context"])

    dispatch_limits = int(job_arguments_dict["dispatch_limits"])
    send_payload_in_batches(api_url, job_arguments_dict["endpoint"], transaction_id, headers, results_payload, dispatch_limits)

    requests.post(f'{api_url}/{job_arguments_dict["endpoint"]}/?transaction_id={transaction_id}', headers=headers, json=results_payload)
    requests.post(f'{api_url}/transactions/{transaction_id}', headers=headers)
    result_request = requests.get(f'{api_url}/transactions/{transaction_id}', headers=headers).content

    transaction_close_response = safe_post_request_with_alert(f'{api_url}/transactions/{transaction_id}', headers=headers)

    if not transaction_close_response:
        logger.error("m=Failed to close transaction.")
    else:
        result_request = requests.get(f'{api_url}/transactions/{transaction_id}', headers=headers).content
        logger.info(f"m=Success!!, transaction status={result_request}")

    logger.info(
        f"m=Success!!, transaction status={result_request}"
    )

if __name__ == '__main__':
    main()