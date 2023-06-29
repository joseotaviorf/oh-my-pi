import json
import requests
from argparse import ArgumentParser

from bietlejuice.clients.db_clients import SparkClient
from quintoandar_logger import QuintoAndarLogger


JOB_NAME = "load_reverse_app_installed"


def create_data_payload(item):
    data = {
        "keyName": "user",
        "type": "CUSTOMER_HAS_APP",
    }
    data["keyValue"] = item["id_user"]
    data["contextFields"] = {"dateTimeLastAccessApp": item["ts_latest_event"]}
    return data


if __name__ == "__main__":
    parser = ArgumentParser(description=JOB_NAME)
    logger = QuintoAndarLogger("MinorityReportAPIClient")

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
        f"""
        SELECT
            COALESCE(id_user, -1) AS id_user,
            MAX(ts_event) AS ts_latest_event
        FROM
            datalake_app_installed.{table}
        WHERE
            ts_event >= '{execution_date}' - INTERVAL "7" DAY
        GROUP BY 1
        """
    )
    df_list = df.toJSON().map(lambda str_json: json.loads(str_json)).collect()
    batches = [df_list[x : x + 100] for x in range(0, len(df_list), 100)].copy()
    total_batches = len(batches)

    session = requests.Session()
    session.headers.update({"Content-Type": "application/json"})

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
