class ReverseMetastoreMapping:
    """Reverse properties mapping for Hive Metastore."""

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

    def get_all_reverse_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """
        database_name = {"reverse_schema_name": f"reverse_{self.schema}"}

        s3_file_path = {
            "reverse_schema_path": f"s3://{self.bucket}/reverse/{self.source}/"
        }

        metastore_info = {}
        metastore_info.update(database_name)
        metastore_info.update(s3_file_path)

        return metastore_info
