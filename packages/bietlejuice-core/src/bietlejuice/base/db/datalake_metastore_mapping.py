import re

from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum

DATALAKE_PREFIX = "datalake_"

# Governed schemas that follow the new naming convention: the database name drops
# the historical ``datalake_`` prefix (e.g. ``ops_finance`` instead of
# ``datalake_ops_finance``). New governed schemas provisioned under this convention
# should be added here.
#
# Historically these were enrich writers with a prefixless override. They are now
# the registered consumption domains (see ``CONSUMPTION_SCHEMAS``). Keep membership
# in sync: every consumption schema must remain prefix-free here.
SCHEMAS_WITHOUT_DATALAKE_PREFIX = frozenset(
    {
        "ops_finance",
        "ops_ss",
        "ops_public",
        "ops_fintech",
        "bi_metrics",
        "forrent_postcontract",
        "forsale_postcontract",
    }
)

# Semantic registry of consumption-layer schemas (prefix-free metastore names).
# May overlap with SCHEMAS_WITHOUT_DATALAKE_PREFIX, but must not be aliased to it —
# that constant only means "drop datalake_", not "this is consumption".
#
# Ambiguity / migration gate (P1):
# For these domains, enrich naming (``datalake_{schema}`` + ``apply_naming_convention``)
# and consumption naming (``{schema}``) produce the SAME physical metastore DB name.
# Schema-name classification therefore always returns ``consumption`` for them — never
# ``enrich``. Until all ``dags/luigijr/enrich_luigijr_*`` declarations flip to
# ``workflow.layer: consumption``, any still-``enrich`` DAG that reads another
# ``ops_*`` / ``forrent_postcontract`` / ``bi_metrics`` table will fail source-layer policy (enrich's
# allow-list does not include consumption). That is intentional; the bulk
# enrich→consumption migration must close before relying on chained reads under
# legacy enrich declarations. Do not remove this registry entry to "fix" that.
CONSUMPTION_SCHEMAS = frozenset(
    {
        "ops_finance",
        "ops_ss",
        "ops_public",
        "ops_fintech",
        "bi_metrics",
        "forrent_postcontract",
        "forsale_postcontract",
    }
)


# Layers routed to this mapper. Single source for both the name and the path
# dict comprehensions in ``get_all_datalake_info`` so the two cannot drift.
_DATALAKE_LAYERS = (
    LayerEnum.TRANSACTIONAL,
    LayerEnum.RAW,
    LayerEnum.CLEAN,
    LayerEnum.CLEAN_STAGING,
    LayerEnum.CORE,
    LayerEnum.ENRICH,
    LayerEnum.CONSUMPTION,
    LayerEnum.WONKA,
    LayerEnum.INGESTION,
    LayerEnum.TRANSFORMATION,
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
        r"^(?:datalake_|core_|transformation_)(?P<schema>[\w|_]+?)(?:_transactional|_raw|_clean|_clean_staging)?$"
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
            # Prefix-free schema name (not consumption_{source}).
            "consumption": f"{self.source}",
            "wonka": "wonka",
            # Three-layer taxonomy. ``ingestion`` mirrors the transactional
            # pattern; ``transformation`` gets its own prefix rather than reusing
            # ``datalake_`` so schema-name classification can tell it apart from
            # enrich (see LayerEnum docstring).
            "ingestion": f"datalake_{self.source}_transactional",
            "transformation": f"transformation_{self.source}",
        }[layer.value]

        # Consumption is already prefix-free (`{source}`); skip the enrich-era
        # datalake_ exception helper so this layer does not depend on it.
        if layer == LayerEnum.CONSUMPTION:
            return database_name
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
            # Storage layout root only — not a schema prefix (schemas stay prefix-free).
            "consumption": f"s3a://{self.bucket}/consumption/{self.source}/",
            "wonka": f"s3a://{self.bucket}/wonka/historical/{self.source}/",
            "ingestion": f"s3a://{self.bucket}/transactional/{self.source}/",
            "transformation": f"s3a://{self.bucket}/transformation/{self.source}/",
        }[layer.value]

    def get_all_datalake_info(self):
        """
        Maps all the databases names and paths according to the parameters.

        :rtype: dict
        """
        database_name = {
            f"db_{layer.value}_name": self.get_full_database_name(layer)
            for layer in _DATALAKE_LAYERS
        }
        s3_files_path = {
            f"db_{layer.value}_path": self.get_full_database_path(layer)
            for layer in _DATALAKE_LAYERS
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
