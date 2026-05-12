import re

from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class ReverseMetastoreMapping(MetastoreMapping):
    """Reverse properties mapping for Hive Metastore."""

    DATABASE_PATTERN = re.compile(r"(?<=^reverse_)(?P<schema>[\w|_]*?)$")

    def get_full_database_name(self, _: LayerEnum = None) -> str:
        """Following the pattern according to the layer and the source (given in the constructor), returns the full database name used in Spark."""
        return f"reverse_{self.source}"

    def get_full_database_path(self, _: LayerEnum = None):
        """Following the pattern according to the layer, source and bucket (given in the constructor), returns the full file path."""
        return f"s3://{self.bucket}/reverse/{self.source}/"

    def get_all_reverse_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """
        database_name = {"reverse_schema_name": self.get_full_database_name()}

        s3_file_path = {"reverse_schema_path": self.get_full_database_path()}

        metastore_info = {}
        metastore_info.update(database_name)
        metastore_info.update(s3_file_path)

        return metastore_info
