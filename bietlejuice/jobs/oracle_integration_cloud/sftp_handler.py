import os
import json
from datetime import datetime
from typing import List, Tuple

import paramiko

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.jobs.oracle_integration_cloud.filename_utils import FileNameUtils
from bietlejuice.base.spark import BaseDBUtils

JOB_NAME = "load_oic_integration_raw"
LOGGER = QuintoAndarLogger(__name__)


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
        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()

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
                if FileNameUtils.extract_report_name(file).lower()
                == hcm_tablename.lower()
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
            self.logger.DEBUG(
                f"Failed to delete file from SFTP: {file_path} - Error: {e}"
            )
            raise
