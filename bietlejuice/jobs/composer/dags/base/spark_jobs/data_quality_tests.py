import json
import logging

from argparse import ArgumentParser

from inmetro.messengers import SlackMessenger
from inmetro.config_reader import ConfigReader
from inmetro.validators import PyDeequValidator
from inmetro.loaders import S3Loader as InmetroS3Loader
from inmetro.builders.validations.pydeequ.validation_suite_builder import (
    ValidationSuiteBuilder,
)
from inmetro.clients import (
    SparkClient as InmetroSparkClient,
    S3Client as InmetroS3Client,
)

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.base.service import ServiceEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum, MetadataTypeEnum
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.spark import BaseDBUtils
from bietlejuice.jobs.composer.pipeline.atlas_quality_metrics_pipeline import (
    AtlasQualityMetricsPipeline,
)


JOB_NAME = "data_quality_tests"

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def create_message_from_validation_results(validation_results):
    suite_name = validation_results["metadata"]["suite_name"]
    status = validation_results["metadata"]["suite_result"].upper()
    n_failures = validation_results["metadata"]["failure"]
    n_success = validation_results["metadata"]["success"]

    failed_columns = set(
        [
            v["column"].split()[0]
            for v in validation_results["validations"]
            if v["status"] != "Success"
        ]
    )

    message = (
        f":warning:\n"
        f"Validation suite: *`{suite_name}`*\n"
        f"Status: *`{status}`*\n\n"
        f"*{n_failures}* out of *{n_failures + n_success}* validations have failed\n"
        f"These are the columns that have failed in at least one check :point_down:\n"
    )
    for column in failed_columns:
        message += f"\t• *`{column}`*\n"

    return message


def parse_complete_table_name(complete_table_name):
    name_components = complete_table_name.split(".")
    if len(name_components) != 2:
        error_msg = (
            f"m={JOB_NAME}, complete_table_name={complete_table_name}, "
            f"msg=The name of the table passed as input is not in the format {{database}}.{{table}}"
        )
        raise ValueError(error_msg)

    database_name = name_components[0]
    table_name = name_components[1]

    return database_name, table_name


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="Environment where the task is executing")
    parser.add_argument(
        "inmetro_bucket",
        type=str,
        help="Bucket that stores all the Inmetro's validation data",
    )
    parser.add_argument("layer", type=str, help="One of LayerEnum values")
    parser.add_argument(
        "relative_file_path",
        type=str,
        help="The `source` name for clean layer."
        " The `source` and/or `context` name for enrich layer. The `schema` for DW layer.",
    )
    parser.add_argument("table_name", type=str)

    args = parser.parse_args()

    env = args.env
    inmetro_bucket = args.inmetro_bucket.replace("s3://", "")
    layer = LayerEnum(args.layer).value
    relative_file_path = args.relative_file_path
    table_name = args.table_name

    return env, inmetro_bucket, layer, relative_file_path, table_name


if __name__ == "__main__":
    (env, inmetro_bucket, layer, relative_file_path, table_name) = parse_args()

    logger.info(
        f"m={JOB_NAME}, env={env}, inmetro_bucket={inmetro_bucket}, layer={layer}, "
        f"relative_file_path={relative_file_path}, table_name={table_name},  msg=Job execution started."
    )

    # ############################# Getting Validation Results ###############################

    validation_file = FileService.get_data_quality_test_file(
        relative_file_path, layer, table_name
    )
    input_config = ConfigReader(validation_file).read()

    spark_client = InmetroSparkClient()
    validation_suite_builder = ValidationSuiteBuilder(spark_client.conn)
    validation_suite = validation_suite_builder.build_validation_suite_from_input_config(
        input_config
    )

    database_name, table_name = parse_complete_table_name(
        input_config.get("table_name")
    )
    input_df = spark_client.read_table(
        database_name=database_name, table_name=table_name
    )
    pydeequ_validator = PyDeequValidator(
        suite_name=f"Pipeline Validations: {database_name}.{table_name}",
        validation_suite=validation_suite,
        client=spark_client,
    )

    validation_results = pydeequ_validator.execute_and_parse(input_df)

    # ################################ Writing to Inmetro's S3 Bucket ##################################

    s3_client = InmetroS3Client()
    s3_loader = InmetroS3Loader(bucket=inmetro_bucket, file_name=f"{table_name}.json")
    destination_directory = f"bietlejuice/{database_name}/{table_name}/validation"

    s3_loader.upload(
        client=s3_client,
        output_parser=validation_results,
        path_name=destination_directory,
    )

    # ############################## Metadata Propagator Call ################################

    base_dbutils = BaseDBUtils()
    if base_dbutils.get_dbutils() is not None:
        dbutils = base_dbutils.get_dbutils()

    metadata_propagator_credentials = json.loads(
        dbutils.secrets.get(
            scope="quintoandar", key=ServiceEnum.METADATA_PROPAGATOR.value
        )
    )
    AtlasQualityMetricsPipeline(
        metadata_propagator_host=metadata_propagator_credentials["host"],
        database_name=database_name,
        table_name=table_name,
        metadata_type=MetadataTypeEnum.QUALITY_METRICS,
        validation_results=validation_results,
    ).run()

    # #################################### Slack Alert ######################################

    if validation_results["metadata"]["suite_result"] != "SUCCESS":
        slack_webhook = dbutils.secrets.get(
            scope="quintoandar", key=APIEnum.AIRFLOW_ALERTS_INMETRO_SLACK_WEBHOOK
        )

        messenger = SlackMessenger(slack_webhook)
        message = create_message_from_validation_results(validation_results)
        messenger.send_message(message)

    logger.info(
        f"m={JOB_NAME}, msg=Data quality tests executed for table {table_name}."
    )
