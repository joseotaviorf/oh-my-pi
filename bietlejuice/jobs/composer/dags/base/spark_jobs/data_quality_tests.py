import glob
import json
import logging

from datetime import datetime
from argparse import ArgumentParser
from pyspark.sql.functions import lit

from inmetro.config_reader import ConfigReader
from inmetro.messengers.slack_messenger import SlackMessenger
from inmetro.validators.pydeequ_validator import PyDeequValidator
from inmetro.clients.spark_client import SparkClient as InmetroSparkClient
from inmetro.builders.validations.pydeequ.validation_suite_builder import (
    ValidationSuiteBuilder,
)

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.composer.services import FileService
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService
from bietlejuice.jobs.composer.pipeline.atlas_quality_metrics_pipeline import (
    AtlasQualityMetricsPipeline,
)
from bietlejuice.jobs.composer.loaders import S3Loader, SparkMetastoreLoader
from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.base.db import DatalakeMetastoreService
from bietlejuice.jobs.composer.base.service import ServiceEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum, MetadataTypeEnum
from bietlejuice.jobs.composer.base.api import APIEnum
from bietlejuice.jobs.composer.base.spark import (
    SparkTableStorageFormat,
    SparkDataFrameService,
    BaseDBUtils,
    spark,
    sc,
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


def write_results_to_datalake(
    env,
    datalake_bucket,
    result_layer,
    result_database,
    result_table,
    validation_results,
):
    source = "inmetro"
    table_name = "data_validations"
    timestamp_execution = datetime.now()
    partition_cols = ["year", "month", "day"]

    s3_loader = S3Loader()
    spark_client = SparkClient()
    spark_metastore_service = SparkMetastoreService(spark_client)
    spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)

    format_options = SparkTableStorageFormat.DEFAULT_RAW
    (
        spark_database_name,
        database_location,
        _,
    ) = DatalakeMetastoreService.get_layer_info(
        env, source, datalake_bucket, LayerEnum.RAW.value
    )

    results_json = json.dumps(validation_results)
    results_df = (
        spark.read.json(sc.parallelize([results_json]))
        .withColumn("layer", lit(result_layer))
        .withColumn("database", lit(result_database))
        .withColumn("table", lit(result_table))
    )
    results_df = (
        SparkDataFrameService()
        .input(results_df)
        .create_year_month_day_columns_from_date(timestamp_execution)
        .output()
    )

    spark_metastore_service.create_database(spark_database_name)

    s3_loader.load_df(
        df=results_df,
        s3_path=f"{database_location}{table_name}",
        format_options=format_options,
        partitions=partition_cols,
        write_mode="append",
    )
    spark_metastore_loader.update_metastore(
        results_df,
        spark_database_name,
        table_name,
        format_options,
        database_location,
        partition_cols,
    )
    spark_metastore_service.create_new_partitions_from_df(
        database_name=spark_database_name,
        table_name=table_name,
        df=results_df,
        partition_cols=partition_cols,
    )
    spark_metastore_service.refresh_table(spark_database_name, table_name)


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


def get_validation_file(file_search_path):
    files = glob.glob(file_search_path, recursive=True)

    if files and files[0]:
        return files[0]

    error_msg = (
        f"m={JOB_NAME}, file_search_path={file_search_path}, "
        f"msg=The validation file for this table could not be reached. "
        f"Check if it is in the right folder and has the same name as the table. "
        f"Expeted location: (composer/base/db/datalake/data_quality/{{context}}/{{layer}}/)"
    )
    raise FileNotFoundError(error_msg)


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="Environment where the task is executing")
    parser.add_argument("datalake_bucket", type=str)
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
    datalake_bucket = args.datalake_bucket
    layer = LayerEnum(args.layer).value
    relative_file_path = args.relative_file_path
    table_name = args.table_name

    return (env, datalake_bucket, layer, relative_file_path, table_name)


if __name__ == "__main__":
    (env, datalake_bucket, layer, relative_file_path, table_name) = parse_args()

    logger.info(
        f"m={JOB_NAME}, env={env}, datalake_bucket={datalake_bucket}, layer={layer}, "
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
    pydeequ_validator = PyDeequValidator(
        suite_name=f"Pipeline Validations: {database_name}.{table_name}",
        validation_suite=validation_suite,
        client=spark_client,
    )

    input_df = spark_client.read_table(
        database_name=database_name, table_name=table_name
    )
    validation_results = pydeequ_validator.execute_and_parse(input_df)

    # ################################ Data Lake Ingestion ##################################

    write_results_to_datalake(
        env=env,
        datalake_bucket=datalake_bucket,
        result_layer=layer,
        result_database=database_name,
        result_table=table_name,
        validation_results=validation_results,
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
