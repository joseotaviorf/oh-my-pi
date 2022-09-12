import re

DW_DATABASE_PATTERN = re.compile("(?<=^dw_)(?P<schema>[\w|_]*?)(?:_staging)?$")


class DwMetastoreMapping:
    """DW properties mapping for Hive Metastore."""

    def __init__(self, schema, bucket):
        """
        Constructor.

        :param schema: the source name or context
        :type schema: str
        :param bucket: the data lake bucket name
        :type bucket: str
        """
        self.schema = schema
        self.bucket = bucket

    def get_all_dw_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """

        metastore_info = {}
        metastore_info.update(self.get_database_dw_info(self.schema))
        metastore_info.update(self.get_path_dw_info(self.schema, self.bucket))

        return metastore_info

    @staticmethod
    def get_database_dw_info(schema):
        """
        Maps all the databases names according to the parameters.

        :rtype: dict
        """

        database_name = {
            "dw_staging_databricks": f"dw_{schema}_staging",
            "dw_schema_databricks": f"dw_{schema}",
        }

        return database_name

    @staticmethod
    def get_path_dw_info(schema, bucket):
        """
        Maps all paths according to the parameters.

        :rtype: dict
        """

        s3_files_path = {
            "dw_staging_path": f"s3a://{bucket}/staging/{schema}/",
            "dw_schema_path": f"s3a://{bucket}/{schema}/",
        }

        return s3_files_path

    @staticmethod
    def get_schema_from_database(database):
        """
        Maps database to its original schema
        IF this database has one of the DW patterns.

        :param database: the database name
        :type database: str
        :rtype: str
        """

        pattern_match = DW_DATABASE_PATTERN.search(database)
        if pattern_match:
            mapped_schema = pattern_match.group("schema")
            return mapped_schema
