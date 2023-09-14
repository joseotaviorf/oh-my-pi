import json
import boto3
import logging

from typing import Tuple
from argparse import ArgumentParser

from pyspark.sql.window import Window
from pyspark.sql import functions as F

from bietlejuice.clients.db_clients import SparkClient

from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_into_sns"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

spark_client = SparkClient()

def main():
    database_name, table_name, event_type, sns_topic_arn = (
        parse_arguments()
    )

    logger.info(
        f"""m=__main__, database_name={database_name}, table_name={table_name},
        event_type={event_type}, sns_topic_arn={sns_topic_arn}"""
    )

    result = prepare_table(database_name, table_name, event_type)
    sns_region = sns_topic_arn.split(":")[3]
    sns_client = boto3.client("sns", region_name=sns_region)

    logger.info(
        f"""m=__main__, sns_region= {sns_region}, sns_client={sns_client}"""
    )

    send_message_dict_to_sns(result, sns_client, sns_topic_arn)


def parse_arguments() -> Tuple[str, str, str, str]:

    parser = ArgumentParser(description=JOB_NAME)
    
    parser.add_argument("database_name", help="Name of the database where the table is")
    parser.add_argument("table_name", help="Name of the table to be loaded")
    parser.add_argument("event_type", help="Type of event to be sent to SNS")
    parser.add_argument("sns_topic_arn", help="ARN of the SNS topic")

    args = parser.parse_args()

    database_name = args.database_name
    table_name = args.table_name
    event_type = args.event_type
    sns_topic_arn = args.sns_topic_arn

    return database_name, table_name, event_type, sns_topic_arn


def prepare_table(database_name: str, table_name: str, event_type: str):
    """
    Retrieves a table from Spark, filters it by a specified execution date, and prepares its payload as a JSON string.
    Parameters:
    - database_name (str): Name of the Spark database containing the desired table.
    - table_name (str): Name of the table to retrieve and process.
    - execution_date (datetime): Date used to filter the table's rows. Rows with a matching year, month, and day are selected.
    """
    df = (
        spark.table(f"{database_name}.{table_name}")
        .selectExpr(
            'sk_region AS id_region', 
            'city_group AS city_group',
            'city_name AS city',
            'neighborhood AS neighborhood',
            'region_tier AS tier',
            'region_tier_type AS tier_type',
            'region_display_name AS region_used_for_m2_average',
            'period_name AS period_name',
            'start_period AS ccv_period',
            'end_period AS ccv_end_period',
            'measure AS avg_price_m2'
        )
        .groupBy(
            'id_region', 
            'city_group',
            'city',
            'neighborhood', 
            'tier',
            'tier_type',
            'region_used_for_m2_average'
        )
        .agg(
            F.collect_list('period_name').alias('period_name'),
            F.collect_list('ccv_period').alias('ccv_period'),
            F.collect_list('ccv_end_period').alias('ccv_end_period'),
            F.collect_list('avg_price_m2').alias('avg_price_m2')
        )
        .withColumn(
            'row_number', 
            F.row_number().over(Window.orderBy('id_region'))
        )
        .withColumn(
            'id',
            F.concat(F.unix_timestamp().cast("string"), F.lpad(F.col("row_number").cast("string"), 6, "0")).cast("bigint")
        )
        .withColumn(
            'ts_load',
            F.date_format(F.current_timestamp(), "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'")
        )
    )

    formatted_df = (
        df
        .withColumn(
            'data', 
            F.arrays_zip(F.col('period_name'), F.col('ccv_period'), F.col('ccv_end_period'), F.col('avg_price_m2'))
        )
        .select('id', 'id_region', 'city_group', 'city', 'neighborhood', 'tier', 'tier_type', 'region_used_for_m2_average', 'ts_load', 'data')
    )

    logger.info(
        f"m=__main__, message=Table retrieved: {formatted_df.count()} rows and {len(formatted_df.columns)} columns."
    )

    historical_data = [region.asDict(recursive=True) for region in formatted_df.collect()]
    payload = []

    for region in historical_data:
        pattern = {"event_type": event_type, "payload": region}
        payload.append(pattern)

    return payload
    

def send_message_dict_to_sns(messages: list, sns_client, sns_topic_arn: str):
    """
    Sends a list of messages to an Amazon SNS topic.
    Parameters:
    - messages (list): A list of dictionaries. Each dictionary represents a message to be sent to the SNS topic.
    - sns_client: An instance of the boto3 SNS client
    - sns_topic_arn (str): The Amazon Resource Name (ARN) of the SNS topic to which messages will be published.
    """
    for message in messages:
        sns_client.publish(
            TopicArn=sns_topic_arn, Message=json.dumps(message, ensure_ascii=False)
        )


if __name__ == "__main__":
    main()