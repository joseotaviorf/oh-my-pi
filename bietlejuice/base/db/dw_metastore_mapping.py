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
        database_name = {
            "dw_staging_databricks": f"dw_{self.schema}_staging",
            "dw_schema_databricks": f"dw_{self.schema}",
        }

        s3_files_path = {
            "dw_staging_path": f"s3a://{self.bucket}/staging/{self.schema}/",
            "dw_schema_path": f"s3a://{self.bucket}/{self.schema}/",
        }

        metastore_info = {}
        metastore_info.update(database_name)
        metastore_info.update(s3_files_path)

        return metastore_info
