import re
from abc import ABC, abstractmethod

from bietlejuice.base.pipeline.layer_enum import LayerEnum


class MetastoreMapping(ABC):
    """Abstract class that maps properties for Hive Metastore"""

    DATABASE_PATTERN: re.Pattern
    """Regex pattern to match the database name. It should have schema as one of its named groups."""

    def __init__(self, source: str, bucket: str) -> None:
        """
        Constructor.

        :param source: the source name or context in metastore
        :type source: str
        :param bucket: the data lake bucket name
        :type bucket: str
        """
        self.source = source
        self.bucket = bucket

    @abstractmethod
    def get_full_database_name(self, layer: LayerEnum = None) -> str:
        """Following the pattern according to the layer and the source (given in the constructor), returns the full database name used in Spark."""

    @abstractmethod
    def get_full_database_path(self, layer: LayerEnum = None):
        """Following the pattern according to the layer, source and bucket (given in the constructor), returns the full file path."""

    @classmethod
    def get_schema_from_database(cls: "MetastoreMapping", database_name: str) -> str:
        """Returns the schema name from the database name."""

        pattern_match = cls.DATABASE_PATTERN.search(database_name)
        if pattern_match:
            mapped_schema = pattern_match.group("schema")
            return mapped_schema
