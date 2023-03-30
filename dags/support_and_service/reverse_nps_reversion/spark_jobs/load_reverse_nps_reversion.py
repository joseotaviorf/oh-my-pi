import json
import requests
from argparse import ArgumentParser

from bietlejuice.clients.db_clients import SparkClient
from quintoandar_logger import QuintoAndarLogger


JOB_NAME = "load_reverse_nps_reversion"

if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    logger = QuintoAndarLogger("AmplitudeAPIClient")

    parser.add_argument("environment")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("minority_report_endpoint")
    parser.add_argument("table")
    parser.add_argument("api_type")
    parser.add_argument("key_name")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    environment = args.environment
    datalake_bucket = args.datalake_bucket
    source = args.source
    minority_report_endpoint = args.minority_report_endpoint
    table = args.table
    api_type = args.api_type
    key_name = args.key_name
    execution_date = args.execution_date

    spark_client = SparkClient()

    df = spark_client.conn.sql(
        f"SELECT * FROM datalake_nps_reversion.{table} WHERE dt_predicted = '{execution_date}'"
    )
    df_rows_list = df.toJSON().map(lambda str_json: json.loads(str_json)).collect()

    headers = {"Content-Type": "application/json"}
    data = {
        "keyName": key_name,
        "type": api_type,
    }

    for row in df_rows_list:
        data["keyValue"] = row["id_contract"]
        data["contextFields"] = row
        resp = requests.post(
            "http://minority-report-api.quintoandar.com.br/profile",
            headers=headers,
            data=json.dumps(data),
        )
        if resp.status_code == 200:
            logger.info(f"Succesfully loaded row {row}")
        else:
            logger.info(resp.raise_for_status())
