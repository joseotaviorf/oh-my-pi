import re
from datetime import datetime
import os
from typing import Optional

from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


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
        filename: str, start_date: datetime.date, end_date: datetime.date
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
