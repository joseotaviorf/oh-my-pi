from argparse import ArgumentParser
from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.spark import BaseDBUtils
import json
import logging
import requests
from quintoandar_logger import QuintoAndarLogger
from bietlejuice.services import ConfigurationService

DATABRICKS_SCOPE = "quintoandar"
JOB_NAME = "load_into_robbyson_api"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def create_results_payload(results_table_path: str, agent_table_path: str, key_join_tables: str, analyst_key_column: str, execution_date: str, context: str) -> list:
    indicators_df = spark.sql(f"SELECT * FROM datalake_static_files_ss.robbyson_indicators WHERE context = '{context}'")
    indicators_content = {row['id_indicator']: row['attributes'] for row in indicators_df.collect()}

    results_df = spark.sql(f"""
        SELECT
            *,
            STRING(MAKE_DATE(year, month, day)) AS date
        FROM
            {results_table_path}
            LEFT JOIN {agent_table_path}
                USING({key_join_tables})
        WHERE
            MAKE_DATE(year, month, day) = DATE('{execution_date}')
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
    parser.add_argument("source", help="Name of the source")
    parser.add_argument(
        "execution_date", help="Date of the execution in the format YYYY-MM-DD"
    )
    parser.add_argument("context", help="Line responsible for processing")
    parser.add_argument("endpoint", help="Api endpoint, where we will send the data")
    parser.add_argument("results_table_path")
    parser.add_argument("agent_table_path")
    parser.add_argument("key_join_tables")
    parser.add_argument("analyst_key_column")

    args = parser.parse_args()

    dag_name = args.dag_name
    environment = args.environment
    source = args.source
    context = args.context
    execution_date = args.execution_date
    endpoint = args.endpoint
    results_table_path =  args.results_table_path
    agent_table_path =  args.agent_table_path
    key_join_tables =  args.key_join_tables
    analyst_key_column =  args.analyst_key_column

    return {
        "dag_name": dag_name,
        "environment": environment,
        "source": source,
        "context": context,
        "execution_date": execution_date,
        "endpoint": endpoint,
        "results_table_path": results_table_path,
        "agent_table_path": agent_table_path,
        "key_join_tables": key_join_tables,
        "analyst_key_column": analyst_key_column
    }

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
    transaction_response = requests.post(f'{api_url}/transactions/', headers=headers).content
    transaction_json = json.loads(transaction_response.decode('utf-8'))
    transaction_id = transaction_json['data']['_id']

    logger.info(
        f"m=Success in getting the credentials., transaction_id={transaction_id}"
    )

    results_payload = create_results_payload(
        job_arguments_dict["results_table_path"],
        job_arguments_dict["agent_table_path"],
        job_arguments_dict["key_join_tables"],
        job_arguments_dict["analyst_key_column"],
        job_arguments_dict["execution_date"],
        job_arguments_dict["context"])

    requests.post(f'{api_url}/{job_arguments_dict["endpoint"]}/?transaction_id={transaction_id}', headers=headers, json=results_payload)
    requests.post(f'{api_url}/transactions/{transaction_id}', headers=headers)
    result_request = requests.get(f'{api_url}/transactions/{transaction_id}', headers=headers).content

    logger.info(
        f"m=Success!!, transaction status={result_request}"
    )

if __name__ == '__main__':
    main()
