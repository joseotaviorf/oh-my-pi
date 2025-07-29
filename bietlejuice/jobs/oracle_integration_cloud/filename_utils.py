import re
from datetime import datetime
import os

from quintoandar_logger import QuintoAndarLogger

LOGGER = QuintoAndarLogger(__name__)


class FileNameUtils:
    """
    Provides static utility methods for common filename manipulations.
    """

    @staticmethod
    def extract_report_name(filename: str) -> str:
        """
        Extracts the report name from a filename based on a specific pattern.
        The expected pattern is: RM_<report_name>_YYYY-MM-DDTHHMMSS.xml (case-insensitive).

        Args:
            filename (str): The name of the file.

        Returns:
            str: The extracted report name if the filename matches the expected pattern.

        Raises:
            ValueError: If the filename does not match the expected pattern.
        """
        pattern = re.compile(r"RM_(.+?)_\d{4}-\d{2}-\d{2}T", re.IGNORECASE)
        match = pattern.search(filename)
        if not match:
            raise ValueError(f"Could not extract report name from filename: {filename}")
        return match.group(1)

    @staticmethod
    def extract_date_from_filename(filename: str) -> str:
        """
        Extracts the date string (YYYY-MM-DD) from a filename based on a specific pattern.
        The expected pattern is: *_YYYY-MM-DDTHHMMSS*.

        Args:
            filename (str): The name of the file.

        Returns:
            str: The extracted date string (YYYY-MM-DD) if the filename matches the pattern.

        Raises:
            ValueError: If the filename does not contain a date in the expected format.
        """
        pattern = re.compile(r"_(\d{4}-\d{2}-\d{2})T")
        match = pattern.search(filename)
        if not match:
            raise ValueError(f"Could not extract date from filename: {filename}")
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
                  Returns False if the date cannot be extracted or is in an invalid format.
        """
        try:
            date_string = FileNameUtils.extract_date_from_filename(filename)
            file_date = datetime.strptime(date_string, "%Y-%m-%d").date()
            return start_date <= file_date <= end_date
        except (ValueError, TypeError) as e:
            LOGGER.warning(f"Could not validate date for filename '{filename}': {e}")
            return False

    @staticmethod
    def build_s3_incoming_path(filename: str, bucket: str) -> str:
        """
        Builds the S3 path for incoming files based on the filename, organizing them
        by report name and date.

        Args:
            filename (str): The name of the file.
            bucket (str): The target S3 bucket name (not used in the returned path).

        Returns:
            str: The S3 path for the incoming file in the format:
                'incoming/<report_name>/YYYY/MM/DD/<filename>'.

        Raises:
            ValueError: If the report name or date cannot be extracted from the filename.
        """
        try:
            base_filename = os.path.basename(filename)
            report_name = FileNameUtils.extract_report_name(base_filename)
            date_str = FileNameUtils.extract_date_from_filename(base_filename)

            date_obj = datetime.strptime(date_str, "%Y-%m-%d").date()
            year = date_obj.strftime("%Y")
            month = date_obj.strftime("%m")
            day = date_obj.strftime("%d")

            path = (
                f"incoming/{report_name.lower()}/{year}/{month}/{day}/{base_filename}"
            )
            return path
        except ValueError as e:
            LOGGER.error(
                f"Could not build S3 path due to invalid filename format: {filename}",
                exc_info=True,
            )
            raise ValueError(
                f"Invalid filename format for S3 path generation: {filename}"
            ) from e
