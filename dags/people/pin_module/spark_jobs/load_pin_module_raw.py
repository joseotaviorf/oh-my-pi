import argparse
import boto3
from datetime import datetime
import json
import os
import re
import subprocess
import sys
from typing import List, Optional, Tuple, Any
import xml.etree.ElementTree as ET

import paramiko
from pyspark.sql import DataFrame, SparkSession
from pyspark.sql.functions import col, dayofmonth, month, now, to_timestamp, year
import traceback

from bietlejuice.base.api.api_enum import APIEnum
from bietlejuice.base.db import DatalakeMetastoreService
from bietlejuice.base.spark import BaseDBUtils, SparkTableStorageFormat
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.services.metastore_services import SparkMetastoreService
from quintoandar_logger import QuintoAndarLogger

JOB_NAME = "load_pin_module_raw"
DATABRICKS_SCOPE = "people"
LOGGER = QuintoAndarLogger(JOB_NAME)

class JobArgumentParser:
    """
    Parses and provides access to job parameters from command-line arguments.
    """

    @staticmethod
    def create_parser() -> argparse.ArgumentParser:
        """
        Creates and returns an argument parser for configuring the job parameters.

        Returns:
            argparse.ArgumentParser: A configured ArgumentParser object.
        """
        parser = argparse.ArgumentParser(description="HCM Integration Pipeline")

        parser.add_argument("environment", help="Environment (e.g., forno, prod)")
        parser.add_argument("datalake_bucket", help="Target S3 bucket")
        parser.add_argument("dag_name", help="DAG name, default schema")
        parser.add_argument("table_name", help="Table name to process")
        parser.add_argument("execution_date", help="Execution date (YYYY-MM-DD)")
        parser.add_argument("partitions", help="Partition columns (comma-separated or JSON list)")
        parser.add_argument("extraction_type", help="Extraction type (full, incremental)")
        parser.add_argument("load_start_date", help="Start date (YYYY-MM-DD)")
        parser.add_argument("load_end_date", help="End date (YYYY-MM-DD)")
        parser.add_argument("extra_details", help="Extra details (JSON string)")

        return parser

    @classmethod
    def parse_args(cls) -> dict:
        """
        Parses command-line arguments into a dictionary.

        Returns:
            dict: A dictionary containing the parsed command-line arguments.
                Includes individual arguments and any key-value pairs from the 'extra_details' JSON string.
                Date strings ('load_start_date', 'load_end_date', 'execution_date') are converted to datetime.date objects.
                The 'partitions' string is parsed into a list of partition columns under the key 'partition_cols'.

        Raises:
            json.JSONDecodeError: If the 'extra_details' argument is not a valid JSON string.
            ValueError: If any of the date arguments ('load_start_date', 'load_end_date', 'execution_date')
                        are not in the 'YYYY-MM-DD' format.
        """
        parser = cls.create_parser()
        args = parser.parse_args()
        args_dict = vars(args)

        extra_details_str = args_dict.pop("extra_details", "{}")
        try:
            extra_details = json.loads(extra_details_str)
        except json.JSONDecodeError as e:
            LOGGER.error(f"Invalid JSON for extra_details: {extra_details_str}. Error: {e}")
            raise

        args_dict.update(extra_details)

        for date_field in ["load_start_date", "load_end_date", "execution_date"]:
            if args_dict.get(date_field):
                try:
                    args_dict[date_field] = datetime.strptime(args_dict[date_field], "%Y-%m-%d").date()
                except ValueError as e:
                    LOGGER.error(f"Invalid date format for {date_field}: {args_dict[date_field]}. Error: {e}")
                    raise

        raw_partitions = args_dict.get("partitions")
        partition_cols = []
        if raw_partitions:
            raw_partitions = raw_partitions.strip()
            if raw_partitions and raw_partitions != "[]":
                try:
                    parsed = json.loads(raw_partitions)
                    if isinstance(parsed, list) and all(isinstance(p, str) for p in parsed):
                        partition_cols = [col.strip() for col in parsed if col.strip()]
                    else:
                        partition_cols = [col.strip() for col in raw_partitions.split(",") if col.strip()]
                except json.JSONDecodeError:
                    partition_cols = [col.strip() for col in raw_partitions.split(",") if col.strip()]

        args_dict["partition_cols"] = partition_cols

        return args_dict

class SFTPHandler:
    """
    Manages connections and operations with an SFTP server.
    """

    def __init__(
        self,
        databricks_scope: str,
        sftp_secret_key: str,
        logger: QuintoAndarLogger = LOGGER,
        job_name: str = JOB_NAME,
    ):
        """
        Initializes the SFTP handler.

        Args:
            databricks_scope (str): The Databricks secrets scope.
            sftp_secret_key (str): The key for the SFTP secrets in Databricks.
            logger (QuintoAndarLogger, optional): The logger instance. Defaults to LOGGER.
            job_name (str, optional): The name of the job. Defaults to JOB_NAME.
        """
        self.scope = databricks_scope
        self.secret_key = sftp_secret_key
        self.logger = logger
        self.job_name = job_name
        self.sftp = None
        self._connect()

    def _get_credentials(self) -> Tuple[str, int, str, str]:
        """
        Retrieves SFTP connection credentials (host, port, username, private key)
        from Databricks secrets.

        Returns:
            Tuple[str, int, str, str]: A tuple containing the SFTP host, port (as an integer),
                                    username, and private key. The keys in the retrieved
                                    secret are converted to lowercase for case-insensitive access.

        Raises:
            Exception: If the secret cannot be retrieved or parsed, or if any of the
                    required keys ('host', 'port', 'username', 'key') are missing
                    in the parsed JSON.
        """
        raw_secret = dbutils.secrets.get(scope=self.scope, key=self.secret_key)
        sftp_secret = json.loads(raw_secret)
        sftp_secret = {k.lower(): v for k, v in sftp_secret.items()}
        return (
            sftp_secret.get("host"),
            int(sftp_secret.get("port")),
            sftp_secret.get("username"),
            sftp_secret.get("key"),
        )

    def _connect(self) -> None:
        """
        Establishes an SFTP connection using the credentials retrieved from Databricks secrets.
        Logs connection attempts and success or failure.

        Raises:
            paramiko.AuthenticationException: If the SFTP server rejects the provided credentials.
            paramiko.SSHException: If there is an error during the SSH connection establishment.
            Exception: For other errors encountered during the connection process,
                    including issues resolving the host or establishing the socket.
        """
        host, port, username, password = self._get_credentials()

        try:
            transport = paramiko.Transport((host, port))
            transport.connect(username=username, password=password)
            self.sftp = paramiko.SFTPClient.from_transport(transport)
        except paramiko.AuthenticationException as e:
            self.logger.error(f"SFTP Authentication failed: {e}")
            raise
        except paramiko.SSHException as e:
            self.logger.error(f"SFTP SSH connection error: {e}")
            raise
        except Exception as e:
            self.logger.error(f"SFTP connection error: {e}")
            raise

    def list_files(
        self,
        hcm_tablename: str,
        start_date: datetime.date,
        end_date: datetime.date,
        default_remote_dir: str = "/home/users/integracao.datalake",
    ) -> List[str]:
        """
        Lists XML files on the SFTP server based on specified filtering criteria.

        Args:
            hcm_tablename (str): The specific HCM table name to filter for. If None or empty,
                                all XML files are considered.
            start_date (datetime.date): The start date (inclusive) to filter files by. Files
                                        with a date in their name before this date are excluded.
                                        If None, no start date filtering is applied.
            end_date (datetime.date): The end date (inclusive) to filter files by. Files with a
                                    date in their name after this date are excluded. If None,
                                    no end date filtering is applied.
            default_remote_dir (str, optional): The default remote directory on the SFTP server
                                                to list files from. Defaults to "/home/users/integracao.datalake".

        Returns:
            List[str]: A list of the full remote paths to the XML files that match the
                    specified filtering criteria.
        """
        remote_dir = self.sftp.getcwd() or default_remote_dir
        remote_files = self.sftp.listdir()
        reports_to_process = [
            file for file in remote_files if file.lower().endswith(".xml")
        ]

        if hcm_tablename:
            reports_to_process = [
                file
                for file in reports_to_process
                if FileNameUtils.extract_report_name(file).lower() == hcm_tablename.lower()
            ]

        if start_date and end_date:
            reports_to_process = [
                file
                for file in reports_to_process
                if FileNameUtils.is_date_in_range(file, start_date, end_date)
            ]

        return [f"{remote_dir}/{file}" for file in reports_to_process]

    def download_file(
        self, remote_path: str, local_dir: str = "/tmp/sftp_downloads"
    ) -> str:
        """
        Downloads a file from the SFTP server to the specified local directory.

        Args:
            remote_path (str): The full path to the file on the SFTP server.
            local_dir (str, optional): The local directory to save the downloaded file.
                                        Defaults to "/tmp/sftp_downloads". This directory
                                        will be created if it does not exist.

        Returns:
            str: The full local path to the downloaded file.
        """
        os.makedirs(local_dir, exist_ok=True)
        filename = os.path.basename(remote_path)
        local_path = f"{local_dir}/{filename}"
        self.sftp.get(remote_path, local_path)
        return local_path

    def delete_file(self, file_path: str) -> None:
        """
        Deletes a file from the SFTP server.

        Args:
            file_path (str): The full path to the file to be deleted on the SFTP server.

        Raises:
            FileNotFoundError: If the specified file does not exist on the SFTP server.
            Exception: For any other errors encountered during the file deletion process.
        """
        try:
            self.sftp.remove(file_path)
        except FileNotFoundError:
            self.logger.DEBUG(f"File not found on SFTP: {file_path}")
            raise
        except Exception as e:
            self.logger.DEBUG(f"Failed to delete file from SFTP: {file_path} - Error: {e}")
            raise


class FileNameUtils:
    """
    Provides static utility methods for common filename manipulations.
    """

    @staticmethod
    def extract_report_name(filename: str) -> Optional[str]:
        """
        Extracts the report name from a filename based on a specific pattern.
        The expected pattern is: RM_<report_name>_YYYY-MM-DDTHHMMSS.xml (case-insensitive for 'RM' and '.xml').

        Args:
            filename (str): The name of the file.

        Returns:
            Optional[str]: The extracted report name if the filename matches the expected pattern,
                        otherwise None.

        Raises:
            Exception: If the filename does not match the expected pattern and the report name cannot be extracted.
        """
        match = re.match(r"RM_(.+?)_\d{4}-\d{2}-\d{2}T", filename)
        if not match:
            LOGGER.error(f"Could not extract report name from filename: {filename}")
            raise
        return match.group(1)

    @staticmethod
    def extract_date_from_filename(filename: str) -> Optional[str]:
        """
        Extracts the date string (YYYY-MM-DD) from a filename based on a specific pattern.
        The expected pattern is: *_YYYY-MM-DDTHHMMSS*.

        Args:
            filename (str): The name of the file.

        Returns:
            Optional[str]: The extracted date string (YYYY-MM-DD) if the filename matches
                        the expected pattern, otherwise None.

        Raises:
            Exception: If the filename does not contain a date in the expected format.
        """
        pattern = re.compile(r"_(\d{4}-\d{2}-\d{2})T")
        match = pattern.search(filename)
        if not match:
            LOGGER.error(f"Could not extract date from filename: {filename}")
            raise
        return match.group(1)

    @staticmethod
    def is_date_in_range(
        filename: str,
        start_date: datetime.date,
        end_date: datetime.date
    ) -> bool:
        """
        Checks if the date extracted from the filename falls within the specified date range (inclusive).

        Args:
            filename (str): The name of the file from which to extract the date.
            start_date (datetime.date): The beginning of the date range (inclusive).
            end_date (datetime.date): The end of the date range (inclusive).

        Returns:
            bool: True if the file's date is within the range, False otherwise.

        Raises:
            Exception: If the date cannot be extracted from the filename or if the
                    extracted date string is not in the expected 'YYYY-MM-DD' format.
        """
        date_string = FileNameUtils.extract_date_from_filename(filename)
        if not date_string:
            return False
        try:
            file_date = datetime.strptime(date_string, "%Y-%m-%d").date()
            return start_date <= file_date <= end_date
        except ValueError as e:
            LOGGER.error(f"Invalid date format in filename: {filename}. Error: {e}")
            raise

    @staticmethod
    def build_s3_incoming_path(filename: str, bucket: str) -> str:
        """
        Builds the S3 path for incoming files based on the filename, organizing them
        by report name and date.

        Args:
            filename (str): The name of the file.
            bucket (str): The target S3 bucket name (although the bucket itself is not
                        part of the returned path).

        Returns:
            str: The S3 path for the incoming file in the format:
                'incoming/<report_name>/YYYY/MM/DD/<filename>'.
                The report name is converted to lowercase.

        Raises:
            Exception: If the report name or date cannot be extracted from the filename,
                    indicating an invalid filename format.
        """
        filename = os.path.basename(filename)
        report_name = FileNameUtils.extract_report_name(filename)
        date_str = FileNameUtils.extract_date_from_filename(filename)

        if not report_name or not date_str:
            error_message = f"Invalid filename format: {filename}"
            LOGGER.error(error_message)
            raise

        date_obj = datetime.strptime(date_str, "%Y-%m-%d").date()
        year = date_obj.strftime("%Y")
        month = date_obj.strftime("%m")
        day = date_obj.strftime("%d")

        path = f"incoming/{report_name.lower()}/{year}/{month:02}/{day:02}/{filename}"
        return path


class PGPHandler:
    """
    Handles PGP encryption and decryption operations.
    """

    def __init__(
        self,
        databricks_scope: str,
        pgp_secret_key: str,
        logger: QuintoAndarLogger = LOGGER,
        job_name: str = "pgp_handler",
    ):
        """
        Initializes the PGP handler.

        Args:
            databricks_scope (str): The Databricks secrets scope.
            pgp_secret_key (str): The key for the PGP secrets in Databricks.
            logger (QuintoAndarLogger, optional): The logger instance. Defaults to LOGGER.
            job_name (str, optional): The name of the job. Defaults to "pgp_handler".
        """
        self.scope = databricks_scope
        self.secret_key = pgp_secret_key
        self.logger = logger
        self.job_name = job_name
        self.passphrase, self.private_key = self._get_credentials()
        self.private_key_path = self._setup_gpg_environment()

    def _get_credentials(self) -> Tuple[str, str]:
        """
        Retrieves the PGP passphrase and private key from Databricks secrets.
        The private key, which may contain escaped newline characters ('\\n'),
        is processed to replace them with actual newline characters ('\n').

        Returns:
            Tuple[str, str]: A tuple containing the PGP passphrase (first element)
                            and the PGP private key (second element).

        Raises:
            Exception: If the secret cannot be retrieved or parsed, or if the
                    required keys ('passphrase', 'private_key') are missing
                    in the parsed JSON.
        """
        pgp_keys = dbutils.secrets.get(scope=self.scope, key=self.secret_key)
        pgp_keys = json.loads(pgp_keys)
        passphrase = pgp_keys["passphrase"]
        private_key = pgp_keys["private_key"].replace("\\n", "\n")
        return passphrase, private_key

    def _setup_gpg_environment(self) -> str:
        """
        Sets up the GPG environment by creating a temporary directory and saving
        the retrieved private key to a file within that directory.

        Returns:
            str: The full path to the saved private key file.

        Raises:
            OSError: If there is an error creating the temporary GPG directory or writing
                    the private key file.
        """
        gpg_dir = "/tmp/gpg_keys"
        os.makedirs(gpg_dir, exist_ok=True)
        private_key_path = f"{gpg_dir}/private.asc"
        with open(private_key_path, "w") as f:
            f.write(self.private_key)
        return private_key_path

    def decrypt_file(self, encrypted_path: str) -> str:
        """
        Decrypts an encrypted file using GPG. It first imports the private key
        and then uses the passphrase to decrypt the provided file.

        Args:
            encrypted_path (str): The full path to the encrypted file.

        Returns:
            str: The full path to the decrypted file. The decrypted filename
                is the original filename with ".XML" replaced by ".decrypted.xml".

        Raises:
            subprocess.CalledProcessError: If the GPG decryption process fails
                                        (non-zero exit code). The error output
                                        from GPG is logged.
            Exception: For any unexpected errors during the decryption process.
        """
        subprocess.run(["gpg", "--batch", "--import", self.private_key_path], check=True)
        decrypted_path = encrypted_path.replace(".XML", ".decrypted.xml")
        try:
            result = subprocess.run(
                [
                    "gpg",
                    "--batch",
                    "--yes",
                    "--pinentry-mode",
                    "loopback",
                    "--passphrase",
                    self.passphrase,
                    "--output",
                    decrypted_path,
                    "--decrypt",
                    encrypted_path,
                ],
                capture_output=True,
                text=True,
                check=True,
            )
        except subprocess.CalledProcessError as e:
            error_message = f"Decryption failed: {e.stderr or e.stdout}"
            self.logger.error(error_message + traceback.format_exc())
            raise
        except Exception as e:
            error_message = f"Unexpected decryption error: {e}"
            self.logger.error(error_message + traceback.format_exc())
            raise
        return decrypted_path


class LocalFileHandler:
    """
    Provides static utility methods for local file system interactions.
    """

    @staticmethod
    def delete_file(file_path: str) -> None:
        """
        Deletes a local file from the filesystem.

        Args:
            file_path (str): The full path to the file to be deleted.

        Raises:
            FileNotFoundError: If the specified file does not exist.
            Exception: For any other errors encountered during the file deletion process
                    (e.g., permission issues).
        """
        try:
            os.remove(file_path)
        except FileNotFoundError:
            LOGGER.DEBUG(f"Could not delete temporary file {file_path}: {file_path}")
            raise
        except Exception as e:
            LOGGER.DEBUG(f"Error deleting temporary file {file_path}: {e}")
            raise

    @staticmethod
    def read_file(file_path: str) -> str:
        """
        Reads the content of a local file using latin1 encoding.

        Args:
            file_path (str): The full path to the file to be read.

        Returns:
            str: The entire content of the file as a string.

        Raises:
            FileNotFoundError: If the specified file does not exist.
            Exception: For any other errors encountered during the file reading process
                    (e.g., permission issues, incorrect encoding).
        """
        try:
            with open(file_path, "r", encoding="latin1") as f:
                file_content = f.read()
            return file_content
        except FileNotFoundError:
            LOGGER.error(f"File not found: {file_path}")
            raise
        except Exception as e:
            LOGGER.error(f"Error reading file {file_path}: {e}")
            raise


class DataFrameHandler:
    """
    Encapsulates common operations performed on Spark DataFrames.
    """

    def __init__(self, logger: QuintoAndarLogger):
        """
        Initializes the DataFrameHandler with a logger.

        Args:
            logger (QuintoAndarLogger): The logger instance to be used.
        """
        self.logger = logger

    def read_xml(self, spark: SparkSession, file_path: str) -> DataFrame:
        """
        Reads an XML file and transforms its content into a Spark DataFrame.
        It assumes the XML structure has a root element containing multiple child elements,
        where each child element represents a record and its sub-elements represent
        columns.

        Args:
            spark (SparkSession): The active SparkSession.
            file_path (str): The full path to the XML file to be read.

        Returns:
            DataFrame: A Spark DataFrame where each row corresponds to a record in the
                    XML file, and the columns are derived from the tags of the
                    sub-elements within each record.

        Raises:
            xml.etree.ElementTree.ParseError: If there is an error parsing the XML file
                                            (e.g., malformed XML).
            Exception: For any other unexpected errors encountered during the XML
                    reading or DataFrame creation process.
        """
        try:
            tree = ET.parse(file_path)
            root = tree.getroot()
            rows = []
            for record in root:
                row = {elem.tag: elem.text for elem in record}
                rows.append(row)

            df = spark.createDataFrame(rows)
            return df
        except ET.ParseError as e:
            self.logger.error(f"Error parsing XML file {file_path}: {e}")
            raise
        except Exception as e:
            self.logger.error(f"Unexpected error reading XML file {file_path}: {e}")
            raise

    def rename_columns_to_lower(self, df: DataFrame) -> DataFrame:
        """
        Renames all columns in the input Spark DataFrame to lowercase.

        Args:
            df (DataFrame): The input Spark DataFrame.

        Returns:
            DataFrame: A new Spark DataFrame with all column names converted to lowercase.

        Raises:
            Exception: If any error occurs during the column renaming process.
        """
        try:
            new_cols = [col.lower() for col in df.columns]
            return df.toDF(*new_cols)
        except Exception as e:
            self.logger.error(f"Error renaming columns to lowercase: {e}")
            raise

    def insert_partitions(
        self,
        df: DataFrame,
        date_column_to_partition: str,
        datetime_format: str = None
        ) -> DataFrame:
        """
        Adds 'year', 'month', and 'day' columns to the DataFrame by converting the
        specified string column to a timestamp. If a datetime format is provided,
        it will be used for the conversion; otherwise, Spark's default timestamp
        conversion will be applied. A 'ts_load' column with the current timestamp
        is also added.

        Args:
            df (DataFrame): The input Spark DataFrame.
            date_column_to_partition (str): The name of the string column containing
                                            the date information to be used for
                                            partitioning.
            datetime_format (str, optional): The format string to use when converting
                                            the date column to a timestamp. If None,
                                            Spark's default conversion is used.
                                            Defaults to None.

        Returns:
            DataFrame: A new Spark DataFrame with the added 'ts_load', 'year', 'month',
                    and 'day' columns. If the specified partition column does not
                    exist, a warning is logged, and the original DataFrame is returned
                    with only the 'ts_load' column added.
        """
        df = df.withColumn("ts_load", now())

        if date_column_to_partition not in df.columns:
            self.logger.warning(f"Partition column '{date_column_to_partition}' does not exist in the DataFrame.")
            return df

        timestamp_col = to_timestamp(col(date_column_to_partition), datetime_format) if datetime_format \
            else to_timestamp(col(date_column_to_partition))

        df = df.withColumn("year", year(timestamp_col))
        df = df.withColumn("month", month(timestamp_col))
        df = df.withColumn("day", dayofmonth(timestamp_col))

        return df


class RawLayerLoader:
    """
    Orchestrates the loading of Spark DataFrames into the raw data lake layer.
    """

    def __init__(
        self,
        spark_client: SparkClient,
        environment: str,
        source: str,
        datalake_bucket: str,
        table_name: str,
        partition_cols: str,
        extraction_type: str = "full",
        logger: QuintoAndarLogger = LOGGER,
    ):
        """
        Initializes the RawLayerLoader.

        Args:
            spark_client (SparkClient): The Spark client instance.
            environment (str): The environment (e.g., forno, prod).
            source (str): The data source identifier.
            datalake_bucket (str): The target S3 bucket name.
            table_name (str): The name of the table to load.
            partition_cols (str): Comma-separated string of partition columns.
            extraction_type (str, optional): The type of extraction ("full" or "incremental"). Defaults to "full".
            logger (QuintoAndarLogger, optional): The logger instance. Defaults to LOGGER.
        """
        self.spark_client = spark_client
        self.environment = environment
        self.source = source
        self.datalake_bucket = datalake_bucket
        self.table_name = table_name
        self.partition_cols = partition_cols
        self.extraction_type = extraction_type.lower()
        self.logger = logger
        self.metastore_service = SparkMetastoreService(spark_client)
        self.s3_loader = S3Loader()
        self.metastore_loader = SparkMetastoreLoader(self.metastore_service)
        self.db_info = DatalakeMetastoreService.get_db_info(
            self.environment, self.source, self.datalake_bucket
        )
        self.database_name = self.db_info["db_raw_databricks"]
        self.database_location = self.db_info["db_raw_path"]

    def load_to_raw(self, df: DataFrame) -> None:
        """
        Orchestrates the process of loading the provided DataFrame into the raw data
        layer. This includes creating the database if it doesn't exist, writing the
        DataFrame to S3, updating the Hive metastore with the new data, and refreshing
        the corresponding table for query availability.

        Args:
            df (DataFrame): The Spark DataFrame to be loaded into the raw layer.

        Raises:
            Exception: If any error occurs during the database creation, data loading
                    to S3, metastore update, or table refresh steps. Specific
                    details of the error will be logged.
        """
        try:
            self._create_database_if_not_exists()
            self._load_df_to_s3(df)
            self._update_metastore(df)
            self._refresh_table()
        except Exception as e:
            self.logger.error(f"Error loading to raw layer: {e}")
            raise

    def _create_database_if_not_exists(self) -> None:
        """
        Checks if the specified database exists in the metastore and creates it
        if it does not. Logs the attempt and any potential errors.

        Raises:
            Exception: If an error occurs during the database creation process
                    in the metastore service.
        """
        try:
            self.metastore_service.create_database(self.database_name)
        except Exception as e:
            self.logger.error(f"Error creating database: {e}")
            raise

    def _load_df_to_s3(self, df: DataFrame) -> None:
        """
        Loads the provided Spark DataFrame to the specified S3 location.
        The storage format and write mode (overwrite for full loads, append for
        incremental loads) are determined based on the configuration. The data
        is partitioned according to the configured partition columns.

        Args:
            df (DataFrame): The Spark DataFrame to be loaded to S3.

        Raises:
            Exception: If any error occurs during the process of loading the
                    DataFrame to S3, including issues with the S3 loader service.
        """
        s3_path = f"{self.database_location}{self.table_name}"
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        mode = "overwrite" if self.extraction_type == "full" else "append"
        try:
            self.s3_loader.load_df(
                df=df,
                s3_path=s3_path,
                format_options=format_options,
                partitions=self.partition_cols,
                mode=mode,
            )
        except Exception as e:
            self.logger.error(f"Error loading DataFrame to S3: {e}")
            raise

    def _update_metastore(self, df: DataFrame) -> None:
        """
        Updates the Hive metastore with the schema and location of the data loaded
        into S3. This ensures that the table is properly defined and queryable by
        Spark SQL or other data access tools. It forces a recreation of the table
        metadata to ensure consistency.

        Args:
            df (DataFrame): A sample Spark DataFrame representing the schema of the
                        data that was loaded to S3. This DataFrame is used to infer
                        the column names and data types for the metastore table.

        Raises:
            Exception: If any error occurs during the metastore update process,
                    including issues communicating with the metastore service.
        """
        format_options = SparkTableStorageFormat.DEFAULT_RAW
        try:
            self.metastore_loader.update_metastore(
                df=df,
                database_name=self.database_name,
                table_name=self.table_name,
                format_options=format_options,
                force_recreate=True,
                database_location=self.database_location,
                partitions=self.partition_cols,
            )
        except Exception as e:
            self.logger.error(f"Error updating metastore: {e}")
            raise

    def _refresh_table(self) -> None:
        """
        Refreshes the metadata of the specified table in the Hive metastore.
        This operation ensures that the metastore has the most up-to-date information
        about the table's schema and data location, especially after new data has
        been loaded or partitions have been added.

        Raises:
            Exception: If an error occurs while attempting to refresh the table
                    metadata in the metastore service.
        """
        try:
            self.metastore_service.refresh_table(self.database_name, self.table_name)
        except Exception as e:
            self.logger.error(f"Error refreshing metastore table: {e}")
            raise


def _initialize_job(
    logger: QuintoAndarLogger, job_name: str, databricks_scope: str
) -> Tuple[SparkSession, SFTPHandler, PGPHandler, Any]:
    """
    Initializes the Spark session and handler classes.
    """
    spark = SparkSession.builder.getOrCreate()
    spark_client = SparkClient()
    s3_resource = boto3.resource("s3")

    pgp_handler = PGPHandler(
        databricks_scope=databricks_scope,
        pgp_secret_key=APIEnum.HCM_PGP,
        logger=logger,
        job_name=job_name,
    )

    sftp_handler = SFTPHandler(
        databricks_scope=databricks_scope,
        sftp_secret_key=APIEnum.HCM_SFTP,
        logger=logger,
        job_name=job_name,
    )

    return spark, sftp_handler, pgp_handler, s3_resource

def _process_file_incoming(
    file: str,
    args: dict,
    sftp_handler: SFTPHandler,
    s3_resource: Any,
    logger: QuintoAndarLogger,
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
    logger.info(f"Encrypted file uploaded to S3 incoming layer: {s3_path}")

    return local_encrypted_path


def _process_file_raw(
    local_decrypted_path: str,
    args: dict,
    spark: SparkSession,
    pgp_handler: PGPHandler,
    logger: QuintoAndarLogger,
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

    df_handler = DataFrameHandler(logger)
    df = df_handler.read_xml(spark, local_decrypted_path)
    df = df_handler.rename_columns_to_lower(df)
    df = df_handler.insert_partitions(df, date_column_to_partition)
    logger.info(f"Processed insert_partitions with param {date_column_to_partition}.")

    raw_layer_loader = RawLayerLoader(
        spark_client=SparkClient(),
        environment=environment,
        source=source,
        datalake_bucket=bucket,
        table_name=table_name,
        partition_cols=partition_cols,
        extraction_type=extraction_type,
        logger=logger,
    )
    raw_layer_loader.load_to_raw(df)


def main():
    """
    Orchestrates the end-to-end data ingestion process from SFTP to the raw
    data lake layer, separating incoming and raw layer processing.
    """
    logger = QuintoAndarLogger(JOB_NAME)

    try:
        spark, sftp_handler, pgp_handler, s3_resource = _initialize_job(
            logger=logger, job_name=JOB_NAME, databricks_scope=DATABRICKS_SCOPE
        )
        args = JobArgumentParser.parse_args()
        files = sftp_handler.list_files(
            hcm_tablename=args["table_name"],
            start_date=args["load_start_date"],
            end_date=args["load_end_date"],
        )
        files = sorted(files)

        for file in files:
            try:
                local_encrypted_path = _process_file_incoming(
                    file=file,
                    args=args,
                    sftp_handler=sftp_handler,
                    s3_resource=s3_resource,
                    logger=logger,
                )

                local_decrypted_path = pgp_handler.decrypt_file(local_encrypted_path)

                _process_file_raw(
                    local_decrypted_path=local_decrypted_path,
                    args=args,
                    spark=spark,
                    pgp_handler=pgp_handler,
                    logger=logger,
                )

                LocalFileHandler.delete_file(local_encrypted_path)
                LocalFileHandler.delete_file(local_decrypted_path)

            except Exception as e:
                logger.error(f"Error processing file {file}: {e}")
                raise

    except Exception as e:
        logger.error(f"An unexpected error occurred in the main function: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
