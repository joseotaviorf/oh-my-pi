import re

from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum

DATALAKE_PREFIX = "datalake_"

# Governed schemas that follow the new naming convention: the database name drops
# the historical ``datalake_`` prefix (e.g. ``ops_finance`` instead of
# ``datalake_ops_finance``). New governed schemas provisioned under this convention
# should be added here.
SCHEMAS_WITHOUT_DATALAKE_PREFIX = frozenset(
    {
        "ops_finance",
    }
)


def apply_naming_convention(source: str, database_name: str) -> str:
    """Drops the ``datalake_`` prefix for governed schemas that follow the new
    naming convention. No-op for every other schema/name."""
    if source in SCHEMAS_WITHOUT_DATALAKE_PREFIX and database_name.startswith(
        DATALAKE_PREFIX
    ):
        return database_name[len(DATALAKE_PREFIX) :]
    return database_name


class DatalakeMetastoreMapping(MetastoreMapping):
    """Datalake properties mapping for Hive Metastore."""

    DATABASE_PATTERN = re.compile(
        r"^(?:datalake_|core_)(?P<schema>[\w|_]+?)(?:_transactional|_raw|_clean|_clean_staging)?$"
    )

    def get_full_database_name(self, layer: LayerEnum = None) -> str:
        """Following the pattern according to the layer and the source (given in the constructor), returns the full database name used in Spark."""
        database_name = {
            "transactional": f"datalake_{self.source}_transactional",
            "raw": f"datalake_{self.source}_raw",
            "clean": f"datalake_{self.source}_clean",
            "core": f"{self.source}",
            "clean_staging": f"datalake_{self.source}_clean_staging",
            "enrich": f"datalake_{self.source}",
            "wonka": "wonka",
        }[layer.value]

        return apply_naming_convention(self.source, database_name)

    @classmethod
    def get_schema_from_database(cls, database_name: str) -> str:
        """Recover the source schema from a database name.

        Extends the base regex (which only matches ``datalake_``/``core_`` prefixes) so
        governed schemas under the new naming convention — which have no ``datalake_``
        prefix (see ``SCHEMAS_WITHOUT_DATALAKE_PREFIX``) — are recovered too, keeping this
        the inverse of ``get_full_database_name``.
        """
        schema = super().get_schema_from_database(database_name)
        if schema is not None:
            return schema
        # No prefix matched: try the governed schemas, stripping the optional layer suffix
        # (e.g. ops_finance / ops_finance_clean -> ops_finance). Exact matches win.
        for governed in SCHEMAS_WITHOUT_DATALAKE_PREFIX:
            if database_name == governed:
                return governed
        for governed in SCHEMAS_WITHOUT_DATALAKE_PREFIX:
            if database_name.startswith(f"{governed}_"):
                return governed
        return None

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
