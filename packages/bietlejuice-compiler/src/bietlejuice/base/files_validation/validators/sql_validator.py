import re

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.files_validation.validators.base_validator import BaseValidator

logger = QuintoAndarLogger("SQLValidator")


class SQLValidator(BaseValidator):
    """
    Extends the BaseValidator to load and run_validator of SQL files
    """

    def __init__(self, file_path, validator_args=None):
        self.file_path = file_path
        self.validator_args = validator_args
        self.sql = self.read_file()

    def run_validator(self, validation_method):
        """
        Executes the validator method passed by the user
        :param validation_method: some SQL validator method
        :return: a boolean indicating the result of the validation
        """
        return validation_method(self.sql, self.validator_args)

    def read_file(self):
        """
        Reads sql file
        :return: a list of sql file rows
        """
        with open(self.file_path) as stream:
            sql = stream.readlines()
        return sql

    @staticmethod
    @logger
    def validate_sql_columns(query_content, required_columns):
        """
        Validates if query has the necessary fields. It's important to note that required_columns must be ordered by
        query output desired
        :param query_content: query file content
        :param required_columns: List of required columns at query output
        :return: True if query string matches Regex pattern, otherwise False
        """
        if not required_columns:
            logger.error(
                "m=validate_sql_columns, msg=You must provide required_columns List (ordered)"
            )
            return False
        tail_column, head_columns = required_columns.pop(), required_columns
        select = r"(select[\s]+(distinct[\s]+)?"
        patterns = [select]
        if head_columns:
            for column in head_columns:
                column_pattern = (
                    f"(.*\\sas\\s+{column}|\\w+\\.{column}|{column})([\\s]+)?,([\\s]+)?"
                )
                patterns.append(column_pattern)

        patterns.append(
            f"([\\s]+)?(.*\\sas\\s+{tail_column}|\\w+\\.{tail_column}|{tail_column})[\\s]+from.*$)"
        )
        pattern_string = "".join(pattern for pattern in patterns)
        pattern = re.compile(pattern_string)
        sql_str = " ".join(query_content)
        sql_str = sql_str.replace("\n", " ").replace("\t", " ").lower()
        return bool(pattern.search(sql_str))
