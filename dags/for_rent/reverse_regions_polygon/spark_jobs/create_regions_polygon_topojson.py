import json
from argparse import ArgumentParser
from datetime import datetime

import boto3
from sedona.register import SedonaRegistrator
from pytopojson import topology
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.consumers.db_consumers import DatabricksConsumer
from bietlejuice.services import S3Service

JOB_NAME = "regions_polygon_topojson_to_s3"
DESTINATION_DATABASE_SOURCE = "ebdb"
S3_PATH_LAYER = "enrich_for_looker"  # TODO: transform this DAG in enrich

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

    parser = ArgumentParser(JOB_NAME)
    parser.add_argument("env")
    parser.add_argument("datalake_bucket")
    parser.add_argument("source")
    parser.add_argument("output_file_path")
    parser.add_argument("output_file_name")
    parser.add_argument("execution_date")

    args = parser.parse_args()

    env = args.env
    datalake_bucket = args.datalake_bucket
    source = args.source
    output_file_path = args.output_file_path
    output_file_name = args.output_file_name
    execution_date = args.execution_date

    logger.info(
        f"m={__name__}, env={env}, datalake_bucket={datalake_bucket}, source={source} "
        f"output_file_path={output_file_path}, output_file_name={output_file_name}, "
        f"execution_date={execution_date}, msg=Job execution started"
    )

    # upload apache sedona lib and registering them to be able to use its functions in query for polygons
    spark_client = SparkClient()
    SedonaRegistrator.registerAll(spark_client.conn)

    database_name, _, _ = DatalakeMetastoreService.get_layer_info(
        env, DESTINATION_DATABASE_SOURCE, datalake_bucket, LayerEnum.CLEAN.value
    )

    query = DAGPackagesPathService.get_query_file_content_in_spark_jobs(
        dag_name=source, table_name=source, layer=LayerEnum.REVERSE.value
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
