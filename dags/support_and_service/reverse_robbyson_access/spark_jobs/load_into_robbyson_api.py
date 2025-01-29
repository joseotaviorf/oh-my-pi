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

def create_results_payload(results_table_path, agent_table_path, key_join_tables_fact, key_join_tables_dim, analyst_key_column, start_date, end_date, context):
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

def parse_arguments():
    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("environment", help="forno/prod values")
    parser.add_argument("start_date", help="Date of the execution in the format YYYY-MM-DD")
    parser.add_argument("end_date", help="End date of the execution in the format YYYY-MM-DD")
    parser.add_argument("dispatch_limits", help="Dispatch limits")
    parser.add_argument("endpoint", help="Api endpoint, where we will send the data")
    parser.add_argument("context", help="Line responsible for processing")
    parser.add_argument("results_table_path")
    parser.add_argument("agent_table_path")
    parser.add_argument("key_join_tables_fact")
    parser.add_argument("key_join_tables_dim")
    parser.add_argument("analyst_key_column")

    args = parser.parse_args()

    return vars(args)

def send_payload_in_batches(api_url, endpoint, transaction_id, headers, payload, batch_size):
    total_batches = len(payload)
    successful_batches = 0

    for i in range(0, total_batches, batch_size):
        batch = payload[i:i + batch_size]
        retry = 2  # Allow a resend attempt

        while retry > 0:
            response = requests.post(
                f'{api_url}/{endpoint}/?transaction_id={transaction_id}',
                headers=headers,
                json=batch
            )

            if response.status_code == 200:
                successful_batches += len(batch)
                logger.info(f"m=Batch sent successfully. Batch_index={i // batch_size}, size={len(batch)}")
                break
            else:
                logger.error(f"m=Error sending batch. Retrying... Batch_index={i // batch_size}, status_code={response.status_code}")
                retry -= 1
                time.sleep(1)  # 1 second delay between attempts

    if successful_batches != total_batches:
        logger.error(f"m=Mismatch in batches sent. Expected={total_batches}, Sent={successful_batches}")
    else:
        logger.info(f"m=All batches sent successfully. Total_batches={total_batches}")
        requests.post(f'{api_url}/transactions/{transaction_id}', headers=headers)
        result_request = requests.get(f'{api_url}/transactions/{transaction_id}', headers=headers).json()
        logger.info(f"m=Transaction completed successfully, transaction_status={result_request}")

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

    transaction_response = requests.post(f'{api_url}/transactions/', headers=headers)

    if transaction_response.status_code == 200:
        transaction_id = transaction_response.json()['data']['_id']
        logger.info(f"m=Transaction started successfully, transaction_id={transaction_id}")
    else:
        logger.error("m=Failed to start transaction.")
        raise SystemExit("Transaction setup failed.")

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

if __name__ == '__main__':
    main()