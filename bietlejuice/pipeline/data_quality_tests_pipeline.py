import json
import logging
from datetime import datetime

import yamale
from yamale import YamaleError

from inmetro.builders.validations.pydeequ.validation_suite_builder import (
    ValidationSuiteBuilder,
)
from inmetro.clients import (
    SparkClient as InmetroSparkClient,
    S3Client as InmetroS3Client,
)
from inmetro.config_reader import ConfigReader
from inmetro.loaders import S3Loader as InmetroS3Loader
from inmetro.validators import PyDeequValidator
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.db import DwMetastoreMapping
from bietlejuice.base.pipeline import LayerEnum, MetadataTypeEnum
from bietlejuice.base.service import ServiceEnum
from bietlejuice.base.service.dag_packages_path_service import DAGPackagesPathService
from bietlejuice.base.spark import BaseDBUtils
from bietlejuice.metadata_propagator_pipeline.datahub_quality_metrics_pipeline import (
    DatahubQualityMetricsPipeline,
)

from pyspark.sql.functions import col, to_timestamp
from pyspark.sql import DataFrame

from bietlejuice.base.notification.gchat_webhooks_enum import GchatWebhooksEnum
from bietlejuice.services.messaging_services.alert_channel_service import (
    AlertChannelService,
)
from bietlejuice.services.messaging_services.gchat_service import GChatService
from bietlejuice.services.messaging_services.message import Message
from bietlejuice.services import ConfigurationService

JOB_NAME = "data_quality_tests"
DATAHUB_URL_TEMPLATE = (
    "{DATAHUB_HOST}/dataset/urn:li:dataset:(urn:li:dataPlatform:trino,"
    "hive.{DATABASE_NAME}.{TABLE_NAME},PROD)/Validation"
)

logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


class DataQualityTestsPipeline:
    def __init__(
        self,
        env: str,
        execution_date: str,
        inmetro_bucket: str,
        layer: LayerEnum,
        relative_file_path: str,
        table_name: str,
        intermediate_path: str,
    ):
        self.env = env
        self.execution_date = execution_date
        self.inmetro_bucket = inmetro_bucket
        self.layer = layer
        self.relative_file_path = relative_file_path
        self.table_name = table_name
        self.intermediate_path = intermediate_path
        self.config_service = ConfigurationService()
        self.spark_client = InmetroSparkClient()

    def run(self):
        logger.info(
            f"m={JOB_NAME}, env={self.env}, inmetro_bucket={self.inmetro_bucket}, layer={self.layer.value}, "
            f"relative_file_path={self.relative_file_path}, table_name={self.table_name},  msg=Job execution started."
        )
        input_configs = self._get_input_configs_from_yaml()
        gchat_webhook = self._get_gchat_webhook(input_configs.get("alert_channel"))

        database_name, table_name = self._parse_complete_table_name(
            input_configs.get("table_name")
        )
        df = self._read_table(database_name, table_name, input_configs)

        # PyDeequValidator fails when try to execute 'column_level_validations' with an empty dataframe.
        if df.isEmpty():
            self._alert_empty_dataframe(
                gchat_webhook,
                database_name,
                table_name,
                input_configs.get("is_incremental") is not None,
            )
        else:
            validation_results = self._execute_test(
                input_configs, database_name, table_name, df
            )
            self._publish_validation_results(
                gchat_webhook, validation_results, database_name, table_name
            )

            logger.info(
                f"m={JOB_NAME}, msg=Data quality tests executed for table {table_name}."
            )

    def _get_gchat_webhook(self, channel_keyword_from_config: str):
        base_dbutils = BaseDBUtils()

        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        alert_channel_service = AlertChannelService(dbutils=dbutils)

        # The service is now generic. The CALLER (this job) decides the default.
        dynamic_gchat_webhook = alert_channel_service.get_gchat_webhook_url(
            channel_keyword=channel_keyword_from_config,
            default_keyword=GchatWebhooksEnum.DATA_QUALITY_DEFAULT,
        )
        logger.info(
            f"Alerts will be sent via webhook. Provided keyword: '{channel_keyword_from_config}'. "
            f"Default fallback: '{GchatWebhooksEnum.DATA_QUALITY_DEFAULT}'"
        )
        return dynamic_gchat_webhook

    def _get_input_configs_from_yaml(self) -> dict:
        validation_file_content = DAGPackagesPathService.get_data_quality_file_content_in_spark_jobs(
            dag_name=self.relative_file_path,
            layer=self.layer.value,
            table_name=self.table_name,
            intermediate_path=self.intermediate_path,
        )

        # ConfigReader(path).read() does not handle S3 paths, so we extracted some of its
        #  behaviours until the lib is enhanced.
        validation_file_content = yamale.make_data(content=validation_file_content)
        self._validate_input_config(input_config=validation_file_content)
        return validation_file_content[0][0]

    def _parse_complete_table_name(self, complete_table_name):
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

    def _read_table(
        self, database_name: str, table_name: str, input_configs: dict
    ) -> DataFrame:
        input_df = self.spark_client.read_table(
            database_name=database_name, table_name=table_name
        )

        is_incremental = input_configs.get("is_incremental")

        if is_incremental:
            incremental_date_column = is_incremental["incremental_date_column"]
            incremental_date_mask = is_incremental["incremental_date_mask"]

            return input_df.where(
                to_timestamp(
                    col(incremental_date_column).cast("string"), incremental_date_mask
                )
                == datetime.strptime(self.execution_date, "%Y-%m-%d")
            )
        else:
            return input_df

    def _alert_empty_dataframe(
        self,
        gchat_webhook: str,
        database_name: str,
        table_name: str,
        is_incremental: bool,
    ):
        message_content = (
            f"⚠️\n"
            f"Validation suite: `Pipeline Validations:`\n"
            f"`{database_name}.{table_name}`\n"
            f"Status: `ERROR`\n\n"
            f"*The dataframe is empty*."
        )

        if is_incremental:
            message_content += f" No data found for the date {self.execution_date}."
        message = Message(content=message_content, destination=gchat_webhook)

        GChatService.send_message(message)

    def _execute_test(
        self, input_configs: dict, database_name: str, table_name: str, df: DataFrame
    ) -> dict:
        validation_suite_builder = ValidationSuiteBuilder(self.spark_client.conn)
        validation_suite = validation_suite_builder.build_validation_suite_from_input_config(
            input_configs
        )
        pydeequ_validator = PyDeequValidator(
            suite_name=f"Pipeline Validations: {database_name}.{table_name}",
            validation_suite=validation_suite,
            client=self.spark_client,
        )

        return pydeequ_validator.execute_and_parse(df)

    def _publish_validation_results(
        self,
        gchat_webhook: str,
        validation_results: dict,
        database_name: str,
        table_name: str,
    ) -> None:
        self._publish_validation_results_to_s3(
            validation_results, database_name, table_name
        )

        # In this case, tests will run on dw_staging, but metadata will associated to dw entities.
        if self.layer.value == "dw_staging":
            database_name = self._mapping_dw_schema(database=database_name)

        self._publish_validation_results_to_metadata_propagator(
            validation_results, database_name, table_name
        )
        is_success = validation_results["metadata"]["suite_result"] == "SUCCESS"
        if not is_success:
            self._publish_failed_validation_results_to_google_chat(
                gchat_webhook, validation_results, database_name, table_name
            )

    def _publish_validation_results_to_s3(
        self, validation_results: dict, database_name: str, table_name: str
    ) -> None:
        s3_client = InmetroS3Client()
        s3_loader = InmetroS3Loader(
            bucket=self.inmetro_bucket, file_name=f"{table_name}.json"
        )
        destination_directory = f"bietlejuice/{database_name}/{table_name}/validation"

        s3_loader.upload(
            client=s3_client,
            output_parser=validation_results,
            path_name=destination_directory,
        )

    def _publish_validation_results_to_metadata_propagator(
        self, validation_results: dict, database_name: str, table_name: str
    ) -> None:
        base_dbutils = BaseDBUtils()
        if base_dbutils.get_dbutils() is not None:
            dbutils = base_dbutils.get_dbutils()

        metadata_propagator_credentials = json.loads(
            dbutils.secrets.get(
                scope="quintoandar", key=ServiceEnum.METADATA_PROPAGATOR.value
            )
        )
        DatahubQualityMetricsPipeline(
            metadata_propagator_host=metadata_propagator_credentials["host"],
            database_name=database_name,
            table_name=table_name,
            metadata_type=MetadataTypeEnum.QUALITY_METRICS,
            validation_results=validation_results,
        ).run()

    def _publish_failed_validation_results_to_google_chat(
        self,
        gchat_webhook: str,
        validation_results: dict,
        database_name: str,
        table_name: str,
    ) -> None:
        datahub_host = self.config_service.get_config("datahub_host")
        message_content = self._create_message_from_validation_results(
            datahub_host, database_name, table_name, validation_results
        )
        message = Message(content=message_content, destination=gchat_webhook)
        GChatService.send_message(message)

    def _create_message_from_validation_results(
        self, datahub_host, database_name, table_name, validation_results
    ):
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
        datahub_validations_url = DATAHUB_URL_TEMPLATE.format(
            DATAHUB_HOST=datahub_host,
            DATABASE_NAME=database_name,
            TABLE_NAME=table_name,
        )
        message = (
            f"⚠️\n"
            f"Validation suite: *`{suite_name}`*\n"
            f"Status: *`{status}`*\n\n"
            f"*{n_failures}* out of *{n_failures + n_success}* validations have failed\n"
            f"These are the columns that have failed in at least one check 👇\n"
        )
        for column in failed_columns:
            message += f"\t• *`{column}`*\n"

        message += f"Check validation details in <{datahub_validations_url}|DataHub>"

        return message

    def _mapping_dw_schema(self, database):
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

    def _check_input_config_schema(self, input_config: list) -> bool:
        """Method extracted from inmetro.config_reader.ConfigReader"""
        try:
            config_schema = yamale.make_schema(ConfigReader.CONFIG_FILE_SCHEMA_PATH)
            yamale.validate(config_schema, input_config)
        except YamaleError as error:
            raise Exception(
                "The input config file does not match the yaml schema. Please, check it again"
            ) from error
        return True

    def _check_validation_sections_exist(self, input_validations: dict) -> bool:
        """Method extracted from inmetro.config_reader.ConfigReader"""
        input_root_validations = list(input_validations.keys())
        intersection = set(ConfigReader.VALIDATION_SECTIONS) & set(
            input_root_validations
        )

        if len(intersection) == 0:
            raise Exception(
                f"The input configuration file does not contain any of the available validation sections: "
                f"{ConfigReader.VALIDATION_SECTIONS}. Please, check your input file."
            )
        return True

    def _check_conflicting_validations_on_same_column(
        self, input_validations: dict
    ) -> bool:
        """Method extracted from inmetro.config_reader.ConfigReader"""
        column_validations = input_validations.get(
            ConfigReader.COLUMN_VALIDATIONS_SECTION, {}
        )

        for column, validations in column_validations.items():
            validation_keys = list(validations.keys())
            intersection = set(validation_keys) & set(
                ConfigReader.CONFLICTING_VALIDATIONS
            )

            if len(intersection) > 1:
                raise Exception(
                    f"There are conflicting validations on column {column}. "
                    f"Please, verify that only one of the following validations occurs: "
                    f"{ConfigReader.CONFLICTING_VALIDATIONS}"
                )
        return True

    def _validate_input_config(self, input_config) -> None:
        """
        Reads the input file, converting it to a dict with all the validations,
        and executes some verifications on the final structure.
        Method extracted from inmetro.config_reader.ConfigReader
        :return: Dict with all the validations contained in the input file.
        """
        input_validations = input_config[0][0]
        self._check_input_config_schema(input_config)
        self._check_validation_sections_exist(input_validations)
        self._check_conflicting_validations_on_same_column(input_validations)
