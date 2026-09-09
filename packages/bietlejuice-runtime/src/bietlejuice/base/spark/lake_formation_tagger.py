"""
Lake Formation LF-tag helper for EMR database creation.

On EMR, newly created Glue databases are stamped with
``data_contract_managed=unknown`` when the tag is missing so they fall
inside the emr-prod LF-tag grant. Existing tag values are never
overwritten. Failures are logged and swallowed so data writes continue.
"""

from __future__ import annotations

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.glue_catalog_helper import GlueCatalogHelper
from bietlejuice.base.spark.runtime_detector import RuntimeDetector

logger = QuintoAndarLogger("LakeFormationTagger")


class LakeFormationTagger:
    _TAG_KEY = "data_contract_managed"
    _DEFAULT_VALUE = "unknown"
    _ensured_databases: set[str] = set()  # per-process dedupe cache

    @staticmethod
    def ensure_database_data_contract_tag(database_name: str) -> None:
        if not RuntimeDetector.is_emr():
            return
        if database_name in LakeFormationTagger._ensured_databases:
            return
        try:
            client = GlueCatalogHelper.get_glue_client()
            if client.database_has_data_contract_tag(database_name):
                LakeFormationTagger._ensured_databases.add(database_name)
                return
            client.add_database_data_contract_tag(
                database_name, LakeFormationTagger._DEFAULT_VALUE
            )
            LakeFormationTagger._ensured_databases.add(database_name)
            logger.info(
                f"m=ensure_database_data_contract_tag, database={database_name}, "
                f"msg=stamped data_contract_managed={LakeFormationTagger._DEFAULT_VALUE}"
            )
        except Exception as exc:  # never break the write
            logger.warning(
                f"m=ensure_database_data_contract_tag, database={database_name}, "
                f"error={exc}, msg=LF-tag ensure failed, continuing"
            )
