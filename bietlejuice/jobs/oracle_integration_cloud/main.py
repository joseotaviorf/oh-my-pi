import boto3
import sys
from typing import Tuple, Any

from pyspark.sql import SparkSession

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.clients.db_clients import SparkClient
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.jobs.oracle_integration_cloud.job_argument_parser import (
    JobArgumentParser,
)
from bietlejuice.jobs.oracle_integration_cloud.sftp_handler import SFTPHandler
from bietlejuice.jobs.oracle_integration_cloud.pgp_handler import PGPHandler
from bietlejuice.jobs.oracle_integration_cloud.filename_utils import FileNameUtils
from bietlejuice.jobs.oracle_integration_cloud.dataframe_handler import DataFrameHandler
from bietlejuice.jobs.oracle_integration_cloud.raw_layer_loader import RawLayerLoader
from bietlejuice.jobs.oracle_integration_cloud.local_file_handler import (
    LocalFileHandler,
)

JOB_NAME = "load_pin_module_raw"
DATABRICKS_SCOPE = "people"


class OICPipeline:
    """
    Orchestrates the end-to-end data ingestion process from SFTP to the raw
    data lake layer.
    """

    def __init__(
        self, job_name: str = JOB_NAME, databricks_scope: str = DATABRICKS_SCOPE
    ):
        self.job_name = job_name
        self.databricks_scope = databricks_scope
        self.logger = QuintoAndarLogger(self.job_name)

    def _initialize_job(self) -> Tuple[SparkSession, "SFTPHandler", "PGPHandler", Any]:
        """
        Initializes the Spark session and handler classes.
        """
        spark = SparkSession.builder.getOrCreate()
        s3_resource = boto3.resource("s3")

        pgp_handler = PGPHandler(
            databricks_scope=self.databricks_scope,
            pgp_secret_key=APIEnum.HCM_PGP,
            logger=self.logger,
            job_name=self.job_name,
        )

        sftp_handler = SFTPHandler(
            databricks_scope=self.databricks_scope,
            sftp_secret_key=APIEnum.HCM_SFTP,
            logger=self.logger,
            job_name=self.job_name,
        )

        return spark, sftp_handler, pgp_handler, s3_resource

    def _process_file_incoming(
        self, file: str, args: dict, sftp_handler: "SFTPHandler", s3_resource: Any
    ) -> str:
        """
        Processes a single file for the incoming layer (download and upload).

        Returns the local path of the downloaded file.
        """
        bucket = args.get("datalake_bucket")

        local_encrypted_path = sftp_handler.download_file(file)

        s3_path = FileNameUtils.build_s3_incoming_path(
            filename=local_encrypted_path, bucket=bucket
        )
        with open(local_encrypted_path, "rb") as f:
            s3_resource.Object(bucket, s3_path).put(Body=f.read())
        self.logger.info(f"Encrypted file uploaded to S3 incoming layer: {s3_path}")

        return local_encrypted_path

    def _process_file_raw(
        self,
        local_decrypted_path: str,
        args: dict,
        spark: SparkSession,
        pgp_handler: "PGPHandler",
    ) -> None:
        """
        Processes a single file for the raw layer (decrypt, transform, load).
        """
        bucket = args.get("datalake_bucket")
        table_name = args.get("table_name")
        environment = args.get("environment")
        source = args.get("raw_custom_schema")
        partition_cols = args.get("partition_cols")
        extraction_type = args.get("extraction_type")
        date_column_to_partition = args.get("date_column_to_partition")

        df_handler = DataFrameHandler(self.logger)
        df = df_handler.read_xml(spark, local_decrypted_path)
        df = df_handler.rename_columns_to_lower(df)
        df = df_handler.insert_partitions(df, date_column_to_partition)
        self.logger.info(
            f"Processed insert_partitions with param {date_column_to_partition}."
        )

        raw_layer_loader = RawLayerLoader(
            spark_client=SparkClient(),
            environment=environment,
            source=source,
            datalake_bucket=bucket,
            table_name=table_name,
            partition_cols=partition_cols,
            extraction_type=extraction_type,
            logger=self.logger,
        )
        raw_layer_loader.load_to_raw(df)

    def run(self):
        """
        Orchestrates the end-to-end data ingestion process from SFTP to the raw
        data lake layer, separating incoming and raw layer processing.
        """
        try:
            spark, sftp_handler, pgp_handler, s3_resource = self._initialize_job()
            args = JobArgumentParser.parse_args()
            files = sftp_handler.list_files(
                hcm_tablename=args["table_name"],
                start_date=args["load_start_date"],
                end_date=args["load_end_date"],
            )
            files = sorted(files)

            for file in files:
                try:
                    local_encrypted_path = self._process_file_incoming(
                        file=file,
                        args=args,
                        sftp_handler=sftp_handler,
                        s3_resource=s3_resource,
                    )

                    local_decrypted_path = pgp_handler.decrypt_file(
                        local_encrypted_path
                    )

                    self._process_file_raw(
                        local_decrypted_path=local_decrypted_path,
                        args=args,
                        spark=spark,
                        pgp_handler=pgp_handler,
                    )

                    LocalFileHandler.delete_file(local_encrypted_path)
                    LocalFileHandler.delete_file(local_decrypted_path)

                except Exception as e:
                    self.logger.error(f"Error processing file {file}: {e}")
                    raise

        except Exception as e:
            self.logger.error(f"An unexpected error occurred in the main function: {e}")
            sys.exit(1)
