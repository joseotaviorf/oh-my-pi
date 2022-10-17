class MetricMetastoreMapping:
    """Metric properties mapping for Hive metastore"""

    def __init__(self, bucket: str, schema: str) -> None:
        self.bucket = bucket
        self.schema = schema

    @staticmethod
    def get_database_path(bucket: str, schema: str) -> str:
        # TO DO:decide if we gonna have maturity as a subfolder.
        db_metric_path = f"s3a://{bucket}/{schema}/"
        return db_metric_path

    @staticmethod
    def get_database_schema(schema: str) -> str:
        db_metric_name = f"metric_{schema}"
        return db_metric_name

    def get_metric_info(self):
        """
        Gets database info for metric layer.

        :return: database_name and database_location
        """
        database_name = self.get_database_schema(self.schema)
        database_location = self.get_database_path(self.bucket, self.schema)

        return database_name, database_location
