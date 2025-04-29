import logging
import json
from datetime import datetime
from argparse import ArgumentParser
from bietlejuice.services import ConfigurationService
from typing import Tuple, Any
import boto3
import time

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_s3"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def parse_arguments() -> Tuple[str, str, str, datetime]:

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("dag_name", help="Name of the database where the table is")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")

    args = parser.parse_args()

    dag_name = args.dag_name
    database_name = args.database_name
    table_name = args.table_name

    return dag_name, database_name, table_name

def format_and_publish_files(database_name: str, table_name: str, s3: Any, bucket: str) -> None:
    logger.info(f'Formatting and publishing files for {database_name}.{table_name}')

    df = spark.table(f"{database_name}.{table_name}")
    index = 0

    for row in df.collect():
        file_key = 'seo/price-range/pending/contentful-neighborhood-%s.json' % row["id_region"]
        has_result = False

        obj = {
            "id": int(row["id_region"]),
            "name": row["name_region"],
            "payload": {}
        }

        if int(row["count_rents"]) > 0:
            obj["payload"].update({
                "maxRentPrice": row["max_rent_price"],
                "avgRentPrice": row["avg_rent_price"],
                "minRentPrice": row["min_rent_price"]
            })
            has_result = True

        if int(row["count_sales"]) > 0:
            obj["payload"].update({
                "maxSalePrice": row["max_sale_price"],
                "avgSalePrice": row["avg_sale_price"],
                "minSalePrice": row["min_sale_price"]
            })
            has_result = True

        if has_result:
            index += 1
            s3.Object(bucket, file_key).put(Body=(bytes(json.dumps(obj).encode('UTF-8'))),
                                           ACL='bucket-owner-full-control', ContentType='application/json')

            if index % 30 == 0:
                time.sleep(1)

    logger.info(f'Finished formatting and publishing files for {database_name}.{table_name}. Published {index} files.')


def main():
    s3 = boto3.resource("s3")

    dag_name, database_name, table_name = parse_arguments()

    config_service = ConfigurationService(dag_name)

    s3_bucket = config_service.get_config("s3_bucket_url")

    format_and_publish_files(database_name, table_name, s3, s3_bucket)

if __name__ == "__main__":
    main()
