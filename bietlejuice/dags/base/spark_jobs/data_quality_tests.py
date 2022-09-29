import json
import logging
from argparse import ArgumentParser

import yamale
from inmetro.builders.validations.pydeequ.validation_suite_builder import (
    ValidationSuiteBuilder,
)
from inmetro.clients import (
    SparkClient as InmetroSparkClient,
    S3Client as InmetroS3Client,
)
from inmetro.config_reader import ConfigReader
from inmetro.loaders import S3Loader as InmetroS3Loader
from inmetro.messengers import SlackMessenger
from inmetro.validators import PyDeequValidator
from quintoandar_logger import QuintoAndarLogger
from yamale import YamaleError

from bietlejuice.base.db import DwMetastoreMapping
from bietlejuice.base.notification.slack_webhooks_enum import SlackWebhooksEnum
from bietlejuice.base.pipeline import LayerEnum, MetadataTypeEnum
from bietlejuice.base.service import ServiceEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.metadata_propagator_pipeline.atlas_quality_metrics_pipeline import (
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


def mapping_dw_schema(database):
    """
    If the database is DW, map it from dw_staging to dw.

    :param database: database name
    :type database: str
    :rtype: str
    """

    schema = DwMetastoreMapping.get_schema_from_database(database)
    if schema:
        database = DwMetastoreMapping.get_database_dw_info(schema)[
            "dw_schema_databricks"
        ]

    return database


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
    parser.add_argument(
        "intermediate_path",
        type=str,
        help="partial path used in some DAGs off of our pattern",
        required=False,
        default="",
    )

    args = parser.parse_args()

    env = args.env
    inmetro_bucket = args.inmetro_bucket.replace("s3://", "")
    layer = LayerEnum(args.layer).value
    relative_file_path = args.relative_file_path
    table_name = args.table_name
    intermediate_path = args.intermediate_path

    return env, inmetro_bucket, layer, relative_file_path, table_name, intermediate_path


def _check_input_config_schema(input_config: list) -> bool:
    """Method extracted from inmetro.config_reader.ConfigReader"""
    try:
        config_schema = yamale.make_schema(ConfigReader.CONFIG_FILE_SCHEMA_PATH)
        yamale.validate(config_schema, input_config)
    except YamaleError as error:
        raise Exception(
            "The input config file does not match the yaml schema. Please, check it again"
        ) from error
    return True


def _check_validation_sections_exist(input_validations: dict) -> bool:
    """Method extracted from inmetro.config_reader.ConfigReader"""
    input_root_validations = list(input_validations.keys())
    intersection = set(ConfigReader.VALIDATION_SECTIONS) & set(input_root_validations)

    if len(intersection) == 0:
        raise Exception(
            f"The input configuration file does not contain any of the available validation sections: "
            f"{ConfigReader.VALIDATION_SECTIONS}. Please, check your input file."
        )
    return True


def _check_conflicting_validations_on_same_column(input_validations: dict) -> bool:
    """Method extracted from inmetro.config_reader.ConfigReader"""
    column_validations = input_validations.get(
        ConfigReader.COLUMN_VALIDATIONS_SECTION, {}
    )

    for column, validations in column_validations.items():
        validation_keys = list(validations.keys())
        intersection = set(validation_keys) & set(ConfigReader.CONFLICTING_VALIDATIONS)

        if len(intersection) > 1:
            raise Exception(
                f"There are conflicting validations on column {column}. "
                f"Please, verify that only one of the following validations occurs: "
                f"{ConfigReader.CONFLICTING_VALIDATIONS}"
            )
    return True


def validate_input_config(input_config) -> None:
    """
    Reads the input file, converting it to a dict with all the validations,
    and executes some verifications on the final structure.

    Method extracted from inmetro.config_reader.ConfigReader

    :return: Dict with all the validations contained in the input file.
    """
    input_validations = input_config[0][0]
    _check_input_config_schema(input_config)
    _check_validation_sections_exist(input_validations)
    _check_conflicting_validations_on_same_column(input_validations)


if __name__ == "__main__":
    (
        env,
        inmetro_bucket,
        layer,
        relative_file_path,
        table_name,
        intermediate_path,
    ) = parse_args()

    logger.info(
        f"m={JOB_NAME}, env={env}, inmetro_bucket={inmetro_bucket}, layer={layer}, "
        f"relative_file_path={relative_file_path}, table_name={table_name},  msg=Job execution started."
    )

    # ############################# Getting Validation Results ###############################
    validation_file_content = DAGPackagesPathService.get_data_quality_file_content_in_spark_jobs(
        dag_name=relative_file_path,
        layer=layer,
        table_name=table_name,
        intermediate_path=intermediate_path,
    )

    # ConfigReader(path).read() does not handle S3 paths, so we extracted some of its
    #  behaviours until the lib is enhanced.
    validation_file_content = yamale.make_data(content=validation_file_content)
    validate_input_config(input_config=validation_file_content)
    input_configs = validation_file_content[0][0]

    spark_client = InmetroSparkClient()
    validation_suite_builder = ValidationSuiteBuilder(spark_client.conn)
    validation_suite = validation_suite_builder.build_validation_suite_from_input_config(
        input_configs
    )

    database_name, table_name = parse_complete_table_name(
        input_configs.get("table_name")
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

    # ################################ Mapping from DW_STAGING to DW  #################################
    # In this case, tests will run on dw_staging, but metadata will associated to dw entities.

    if layer == "dw_staging":
        database_name = mapping_dw_schema(database=database_name)

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
            scope="quintoandar", key=SlackWebhooksEnum.ALERTS_AIRFLOW_DE_DAGS_INMETRO
        )

        messenger = SlackMessenger(slack_webhook)
        message = create_message_from_validation_results(validation_results)
        messenger.send_message(message)

    logger.info(
        f"m={JOB_NAME}, msg=Data quality tests executed for table {table_name}."
    )
