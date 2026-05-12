import re

from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class MetricMetastoreMapping(MetastoreMapping):
    """Metric properties mapping for Hive metastore"""

    DATABASE_PATTERN = re.compile(r"(?<=^metric_)(?P<schema>[\w|_]*?)$")

    @staticmethod
    def get_database_path(bucket: str, schema: str) -> str:
        # TO DO:decide if we gonna have maturity as a subfolder.
        db_metric_path = f"s3a://{bucket}/{schema}/"
        return db_metric_path

    @staticmethod
    def get_database_schema(schema: str) -> str:
        db_metric_name = f"metric_{schema}"
        return db_metric_name

    def get_full_database_name(self, _: LayerEnum = None) -> str:
        """Following the pattern according to the layer and the source (given in the constructor), returns the full database name used in Spark."""
        return MetricMetastoreMapping.get_database_schema(self.source)

    def get_full_database_path(self, _: LayerEnum = None):
        """Following the pattern according to the layer, source and bucket (given in the constructor), returns the full file path."""
        return MetricMetastoreMapping.get_database_path(self.bucket, self.source)

    def get_metric_info(self):
        """
        Gets database info for metric layer.

        :return: database_name and database_location
        """
        database_name = self.get_database_schema(self.source)
        database_location = self.get_database_path(self.bucket, self.source)

        return database_name, database_location
