import logging
import json
from argparse import ArgumentParser
from collections import OrderedDict

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.s3_consumer import S3Consumer
from bietlejuice.jobs.composer.services.schema_service import SchemaService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService

JOB_NAME = "load_zendesk_tickets_custom_fields_metastore"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)

if __name__ == "__main__":
    parser = ArgumentParser(description="load_zendesk_tickets_custom_fields_metastore")
    parser.add_argument("execution_date", type=str, help="execution date in str format")
    parser.add_argument("database", type=str, help="database name")
    parser.add_argument("table_name", type=str, help="table name")
    parser.add_argument("partition_col", type=str, help="partition column name")
    parser.add_argument("s3_file_path", type=str, help="table file path in s3")
    parser.add_argument("s3_file_format", type=str, help="table file format in s3")
    parser.add_argument(
        "s3_file_read_options",
        type=str,
        help="read options for table files in json format",
    )

    args = parser.parse_args()
    execution_date = args.execution_date
    database = args.database
    table_name = args.table_name
    partition_col = args.partition_col
    s3_file_path = args.s3_file_path
    s3_file_format = args.s3_file_format
    s3_file_read_options = json.loads(args.s3_file_read_options)

    spark_client = SparkClient(s3_file_read_options)
    spark_metastore_service = SparkMetastoreService(spark_client)

    spark_metastore_service.create_database(database)
    if table_name not in spark_metastore_service.get_table_names(database):

        s3_consumer = S3Consumer(spark_client)
        df = s3_consumer.get_data_from_file(s3_file_path, s3_file_format)

        df_schema = SchemaService.get_schema_from_dataframe(df)
        spark_metastore_service.create_external_table(
            database,
            table_name,
            s3_file_path,
            df_schema,
            [partition_col],
            s3_file_format,
        )
        spark_metastore_service.repair_table_partitions(database, table_name)
    else:
        partitions = [OrderedDict([(partition_col, execution_date)])]
        spark_metastore_service.add_partitions(database, table_name, partitions)
