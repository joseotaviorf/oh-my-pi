import re

from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class DatalakeMetastoreMapping(MetastoreMapping):
    """Datalake properties mapping for Hive Metastore."""

    DATABASE_PATTERN = re.compile(
        r"^(?:datalake_|core_)(?P<schema>[\w|_]+?)(?:_transactional|_raw|_clean|_clean_staging)?$"
    )

    def get_full_database_name(self, layer: LayerEnum = None) -> str:
        """Following the pattern according to the layer and the source (given in the constructor), returns the full database name used in Spark."""
        return {
            "transactional": f"datalake_{self.source}_transactional",
            "raw": f"datalake_{self.source}_raw",
            "clean": f"datalake_{self.source}_clean",
            "core": f"{self.source}",
            "clean_staging": f"datalake_{self.source}_clean_staging",
            "enrich": f"datalake_{self.source}",
            "wonka": "wonka",
        }[layer.value]

    def get_full_database_path(self, layer: LayerEnum = None):
        """Following the pattern according to the layer, source and bucket (given in the constructor), returns the full file path."""
        return {
            "transactional": f"s3a://{self.bucket}/transactional/{self.source}/",
            "raw": f"s3a://{self.bucket}/raw/{self.source}/",
            "clean": f"s3a://{self.bucket}/clean/{self.source}/",
            "core": f"s3a://{self.bucket}/core/{self.source}/",
            "clean_staging": f"s3a://{self.bucket}/clean_staging/{self.source}/",
            "enrich": f"s3a://{self.bucket}/enrich/{self.source}/",
            "wonka": f"s3a://{self.bucket}/wonka/historical/{self.source}/",
        }[layer.value]

    def get_all_datalake_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """
        database_name = {
            f"db_{layer.value}_name": self.get_full_database_name(layer)
            for layer in (
                LayerEnum.TRANSACTIONAL,
                LayerEnum.RAW,
                LayerEnum.CLEAN,
                LayerEnum.CLEAN_STAGING,
                LayerEnum.CORE,
                LayerEnum.ENRICH,
                LayerEnum.WONKA,
            )
        }
        s3_files_path = {
            f"db_{layer.value}_path": self.get_full_database_path(layer)
            for layer in (
                LayerEnum.TRANSACTIONAL,
                LayerEnum.RAW,
                LayerEnum.CLEAN,
                LayerEnum.CLEAN_STAGING,
                LayerEnum.CORE,
                LayerEnum.ENRICH,
                LayerEnum.WONKA,
            )
        }

        metastore_info = {}
        metastore_info.update(database_name)
        metastore_info.update(s3_files_path)
        return metastore_info

    def get_datalake_info_from_layer(self, layer):
        """
        Gets database info for given layer.

        :param layer: raw, clean, enrich or clean_staging layers
        :type layer: str
        :return: specified layer info
        """
        metastore_info = self.get_all_datalake_info()

        datalake_database_name = metastore_info[f"db_{layer}_name"]
        database_location = metastore_info[f"db_{layer}_path"]

        return datalake_database_name, database_location
