import json
import logging
import requests
import time
from datetime import datetime
from typing import Tuple
from argparse import ArgumentParser
import numpy as np

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
    search_mapping = {
                        'dsat_bot': 'csat',
                        'dsat_visitas': 'csat',
                        'dsat_customer_relationship':'csat',
                        'dsat_novas_pesquisas':'csat',
                        'dsat_diligencia': 'csat',
                        'onboarding': 'nps',
                        'ongoing':'nps',
                        'offboarding':'nps',
                        'lost': 'nps',
                        'pp_multi': 'nps',
                        'novas_pesquisas':'nps',
                        'end_of_process': 'nps'
                    }
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
                LIMIT 20
            """
        )
    if search_mapping[table_name] == 'csat':
        campaign_title = "csat_campanha"
    else:
        campaign_title = "nome_campanha"
        
    for col in df.columns:
        if dict(df.dtypes)[col] == 'int':
            df = df.fillna({col: np.NaN })
        else:
            df = df.fillna({col: ""})
    
    nps_content = {row['feedback_id']: {k: v for k, v in row.asDict().items()} for row in df.collect()}
    results_list = []
    for key, value in nps_content.items():
        result_dict = {}
        result_dict["posted_at"] = value['posted_at']
        result_dict["text"] = value['text']
        result_dict["language"] = 'pt-BR'
        result_dict["kind"] = {
                "name": search_mapping[table_name],
                "fields": {
                "author_id": str(value['author_id']),
                "author_name": str(value['author_id']),
                "account_id": "Quinto Andar",
                "title": value[f'{campaign_title}'],
                "rating": value['rating']
                    }
                }
        result_dict["additional_fields"] = {k: str(v) for k, v in value.items()}
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
        for feedback_id in x.keys():
            data = x[feedback_id]
            response = requests.put(
                f'{api_url}/{endpoint}/{feedback_id}',
                headers=headers,
                data=json.dumps(data)
                )

            if response.status_code == 201:
                logger.info(f"m=Batch sent successfully. Dispatch number={successful_dispatches}, total size={total_dispatches}")
                successful_dispatches += 1
                time.sleep(1)
                break
            else:
                logger.error(f"m=Error sending batch. Retrying... Batch_index={successful_dispatches}, status_code={response.status_code}. Message={response.text}")
                errors_dispatches.append(x)

    if successful_dispatches != total_dispatches:
        logger.error(f"m=Mismatch in data sent. Expected={total_dispatches}, Sent={successful_dispatches}")
        logger.info(f"Starting retry process for {len(errors_dispatches)} records")
        retry_success = 0
        for x in errors_dispatches:
            for feedback_id in x.keys():
                data = x[feedback_id]
                response = requests.put(
                    f'{api_url}/{endpoint}/{feedback_id}',
                    headers=headers,
                    data=json.dumps(data)
                    )
            if response.status_code == 201:
                logger.info(f"m=Batch sent successfully. Retry number={retry_success}, total retry size={errors_dispatches}")
                retry_success += 1
            else:
                logger.error(f"m=Error sending retry records.feedback_id={feedback_id}, Batch_index={retry_success}, status_code={response.status_code}. Message={response.text}")
                
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