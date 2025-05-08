import os
import subprocess
import traceback
from typing import Tuple
import json

from quintoandar_logger import QuintoAndarLogger
from bietlejuice.base.spark import BaseDBUtils

LOGGER = QuintoAndarLogger(__name__)


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
        base_dbutils = BaseDBUtils()
        dbutils = base_dbutils.get_dbutils()
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
        subprocess.run(
            ["gpg", "--batch", "--import", self.private_key_path], check=True
        )
        decrypted_path = encrypted_path.replace(".XML", ".decrypted.xml")
        try:
            subprocess.run(
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
