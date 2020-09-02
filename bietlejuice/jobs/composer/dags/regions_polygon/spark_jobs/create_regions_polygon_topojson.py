import logging
import json
import boto3
from argparse import ArgumentParser
from datetime import datetime
from pytopojson import topology
from geospark.register import upload_jars
from geospark.register import GeoSparkRegistrator

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.composer.base.db import (
    QUERIES_DATALAKE_PATH,
    DatalakeMetastoreService,
)
from bietlejuice.jobs.composer.base.pipeline import LayerEnum
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.consumers.db_consumers import DatabricksConsumer
from bietlejuice.jobs.composer.services import FileService, S3Service

JOB_NAME = "regions_polygon_topojson_to_s3"
SOURCE = "ebdb"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_json_from_json_string(geojson_str):
    """
    Formatting json str to remove additional backslash (\)
    and quotation marks (") from before and after curly brackets ({ and })
    to be able to load it as a json object
    :param geojson_str: json in string format
    :return: json object
    """
    geojson_str = geojson_str.replace("\\", "").replace('"{', "{").replace('}"', "}")
    return json.loads(geojson_str)


if __name__ == "__main__":

    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="forno/prod values")
    parser.add_argument("datalake_bucket", type=str, help="datalake bucket")
    parser.add_argument(
        "relative_full_query_path",
        type=str,
        help="relative full query path for sql file (from datalake-queries path)",
    )
    parser.add_argument(
        "output_file_path", type=str, help="file path where file will be created"
    )
    parser.add_argument(
        "output_file_name",
        type=str,
        help="file name that will be created, with extension",
    )
    parser.add_argument("execution_date")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    relative_full_query_path = args.relative_full_query_path
    output_file_path = args.output_file_path
    output_file_name = args.output_file_name
    execution_date = args.execution_date

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, "
        f"relative_full_query_path={relative_full_query_path}, output_file_path={output_file_path}, "
        f"output_file_name={output_file_name}, execution_date={execution_date}, "
        "msg=Job execution started"
    )

    # upload geospark lib jars and registering them to be able to use its functions in query for polygons
    upload_jars()
    spark_client = SparkClient()
    GeoSparkRegistrator.registerAll(spark_client.conn)

    database_name, database_location, athena_database_name = DatalakeMetastoreService.get_layer_info(
        env, SOURCE, datalake_bucket, LayerEnum.CLEAN.value
    )

    query = FileService.get_query_from_file_name(
        f"{QUERIES_DATALAKE_PATH}{relative_full_query_path}"
    )

    databricks_consumer = DatabricksConsumer({"db": database_name}, spark_client)
    df = databricks_consumer.get_data_from_query(query)

    # formatting json string returned into df and returning json object
    geojson_json = parse_json_from_json_string(df.first()[0])

    topology_ = topology.Topology()
    topojson_dict = topology_({"5a_subregion_polygons": geojson_json})
    topojson_json = json.dumps(topojson_dict)

    date = datetime.strptime(execution_date, "%Y-%m-%d")
    year, month, day = date.year, date.month, date.day
    s3_service = S3Service(boto3.resource("s3"))

    # saving file twice, once in main folder and another in year/month/day folder
    s3_service.upload_file(
        topojson_json,
        f"{output_file_path}/year={year}/month={month}/day={day}/{output_file_name}",
    )
    s3_service.upload_file(topojson_json, f"{output_file_path}/{output_file_name}")
