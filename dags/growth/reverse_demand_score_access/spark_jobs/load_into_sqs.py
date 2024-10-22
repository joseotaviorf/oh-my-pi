import logging
import json
from datetime import datetime
from argparse import ArgumentParser
from bietlejuice.services import ConfigurationService
from typing import Tuple
import boto3

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sqs"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

def parse_arguments() -> Tuple[str, str, str, datetime]:
    """
    Parse the arguments passed to the job.
    Returns a tuple with the database name, table name, event type, ARN of the SQS topic and execution date.
    """

    parser = ArgumentParser(description=JOB_NAME)

    parser.add_argument("dag_name", help="Name of the database where the table is")
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")

    args = parser.parse_args()

    dag_name = args.dag_name
    database_name = args.database_name
    table_name = args.table_name

    return dag_name, database_name, table_name

def transform_payload(database_name, table_name):
    logger.info(f'Transforming payload for {database_name}.{table_name}')

    df = spark.table(f"{database_name}.{table_name}")

    df = df.select(['id_house', 'demand_score', 'dt_snapshot'])

    df = df.withColumnRenamed('id_house', 'houseId') \
            .withColumnRenamed('demand_score', 'listingAgeDemandScore') \
            .withColumnRenamed('dt_snapshot', 'eventDate')

    df = df.withColumn('eventDate', (df['eventDate'].cast('timestamp').cast('long') * 1000))

    logger.info(f'Payload adjusted for {database_name}.{table_name}')

    message_contents = df.collect()

    payload = [{"eventDate": row["eventDate"], "payload": {"houseId": row["houseId"], "listingAgeDemandScore": row["listingAgeDemandScore"]}} for row in message_contents]

    return payload

def send_message(sqs_client, queue_url, data):
  
    logger.info(f'Sending message to SQS queue {queue_url}')

    message_attributes = {"contentType": {
                    "DataType": "String",
                    "StringValue": "application/json"
                }}
    
    try:
        for message in data:
            message_body = json.dumps(message)
            
            logger.info(f'Sending message to SQS: {message_body}')

            sqs_client.send_message(
                QueueUrl=queue_url,
                MessageBody=message_body,
                MessageAttributes=message_attributes
            ) 
        logger.info(f'Message send successfully')
        
    except Exception as e:
        logger.error(f'Error sending message to SQS: {e}')
        logger.error(f'The last message sent was {message}')

def main():
    sqs = boto3.client('sqs', region_name='us-east-1')

    dag_name, database_name, table_name = parse_arguments()

    config_service = ConfigurationService(dag_name)

    queue_url = config_service.get_config("sqs_queue_url")
    
    payload = transform_payload(database_name, table_name)
    
    send_message(sqs, queue_url, payload)

if __name__ == "__main__":
    main()