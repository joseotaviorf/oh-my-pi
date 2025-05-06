import os

from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


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
