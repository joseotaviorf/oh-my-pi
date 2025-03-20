import json
import logging
import requests
import time
from datetime import datetime
from typing import Tuple
from argparse import ArgumentParser

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.services import ConfigurationService
from pyspark.sql.functions import date_format
from quintoandar_logger import QuintoAndarLogger


DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_into_birdie_api"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def create_results_payload(database_name, table_name, execution_date):
    df = spark.sql(
            f"""
                SELECT 
                    * 
                FROM 
                    {database_name}.{table_name} 
                WHERE 
                    year={execution_date.year} 
                    AND month={execution_date.month} 
                    AND day={execution_date.day}
            """
        )
    nps_df = df.withColumn("ts_answer", date_format("ts_answer", "yyyy-MM-dd"))
    nps_df = nps_df.fillna("")
    nps_content = {
        row['sk_nps_answer']: {"uuid_person": row['uuid_person'], 
                            "score": row['score'], 
                            "campaign_name": row['campaign_name'],
                            "comment": row['comment'], 
                            "score_category": row['score_category'], 
                            "ts_answer": row['ts_answer'],
                            "sk_user": row['sk_user']
                            } 
        for row in nps_df.collect()}

    results_list = []
    for key, value in nps_content.items():
        result_dict = {}
        result_dict["posted_at"] = value['ts_answer'] + "T00:00:00Z"
        result_dict["text"] = value['comment']
        result_dict["language"] = 'en'
        result_dict["kind"] = {
            "name": "nps",
            "fields": {
                "author_id": value['uuid_person'],
                "author_name": str(value['sk_user']),
                "account_id": "Quinto Andar",
                "title": value['campaign_name'],
                "rating": value['score']
            }
        }
        result_dict["additional_fields"] = {
            "classification": value['score_category']
        }
        results_json = {    
            key: result_dict
        }
        results_list.append(results_json)
    return results_list

def parse_arguments() -> Tuple[str, str, str, str, datetime, str, str]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the DAG name, database name, table name, event type, and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("dag_name", help="Name of the DAG")
    parser.add_argument("database_name", help="Database where data is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )
    parser.add_argument("endpoint", help="Endpoint to send the data to")
    parser.add_argument("api_url", help="URL to send the data to")

    args = parser.parse_args()

    dag_name = args.dag_name
    database_name = args.database_name
    table_name = args.table_name
    execution_date = datetime.fromisoformat(args.execution_date)
    endpoint = args.endpoint
    api_url = args.api_url

    return dag_name, database_name, table_name, execution_date, endpoint, api_url

def send_payload(api_url, endpoint, headers, results_list):
    total_dispatches = len(results_list)
    successful_dispatches = 0
    errors_dispatches = []

    for x in results_list:
        for sk_nps_answer in x.keys():
            data = x[sk_nps_answer]
            response = requests.put(
                f'{api_url}/{endpoint}/{sk_nps_answer}',
                headers=headers,
                data=json.dumps(data)
                )

            if response.status_code == 201:
                logger.info(f"m=Batch sent successfully. Dispatch number={successful_dispatches}, total size={total_dispatches}")
                successful_dispatches += 1
                time.sleep(1)
                break
            else:
                logger.error(f"m=Error sending batch. Retrying... Batch_index={successful_dispatches}, status_code={response.status_code}")
                errors_dispatches.append(x)

    if successful_dispatches != total_dispatches:
        logger.error(f"m=Mismatch in data sent. Expected={total_dispatches}, Sent={successful_dispatches}")
        logger.info(f"Starting retry process for {len(errors_dispatches)} records")
        retry_success = 0
        for x in errors_dispatches:
            for sk_nps_answer in x.keys():
                data = x[sk_nps_answer]
                response = requests.put(
                    f'{api_url}/{endpoint}/{sk_nps_answer}',
                    headers=headers,
                    data=json.dumps(data)
                    )
            if response.status_code == 201:
                logger.info(f"m=Batch sent successfully. Retry number={retry_success}, total retry size={errors_dispatches}")
                retry_success += 1
            else:
                logger.error(f"m=Error sending retry records. Sk_nps_answer={sk_nps_answer}, Batch_index={retry_success}, status_code={response.status_code}")
    else:
        logger.info(f"m=All data sent successfully. Total_dispatches={total_dispatches}") 

def main():
    dag_name, database_name, table_name, execution_date, endpoint, api_url = (
        parse_arguments()
    )

    base_dbutils = BaseDBUtils()
    global dbutils
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    api_key = dbutils.secrets.get(scope=DATABRICKS_SCOPE, key=APIEnum.BIRDIE)
    headers = {
      'Content-type': 'application/json', 
      'Authorization': api_key}

    results_payload = create_results_payload(database_name, table_name, execution_date)

    send_payload(api_url, endpoint, headers, results_payload)

if __name__ == '__main__':
    main()