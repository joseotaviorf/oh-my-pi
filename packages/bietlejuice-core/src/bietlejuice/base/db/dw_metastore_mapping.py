import re

from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class DwMetastoreMapping(MetastoreMapping):
    """DW properties mapping for Hive Metastore."""

    DATABASE_PATTERN = re.compile(r"(?<=^dw_)(?P<schema>[\w|_]*?)(?:_staging)?$")

    def get_full_database_name(self, layer: LayerEnum = None) -> str:
        """Following the pattern according to the layer and the source (given in the constructor), returns the full database name used in Spark."""
        database_info = DwMetastoreMapping.get_database_dw_info(self.source)
        if layer == LayerEnum.DW:
            return database_info["dw_schema_databricks"]
        else:
            return database_info["dw_staging_databricks"]

    def get_full_database_path(self, layer: LayerEnum = None):
        """Following the pattern according to the layer, source and bucket (given in the constructor), returns the full file path."""
        path_info = DwMetastoreMapping.get_path_dw_info(self.source, self.bucket)
        if layer == LayerEnum.DW:
            return path_info["dw_schema_path"]
        else:
            return path_info["dw_staging_path"]

    def get_all_dw_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """

        metastore_info = {}
        metastore_info.update(self.get_database_dw_info(self.source))
        metastore_info.update(self.get_path_dw_info(self.source, self.bucket))

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
