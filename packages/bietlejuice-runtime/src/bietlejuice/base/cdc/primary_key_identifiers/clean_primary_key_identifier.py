from typing import List

import yaml
from delta.tables import DeltaTable

from bietlejuice.base.cdc.primary_key_identifiers.primary_key_identifier import (
    PrimaryKeyIdentifier,
)
from bietlejuice.base.spark.base_spark import BaseSparkContext
from bietlejuice.services.storage_services import VolumeMapper, VolumeService


class CleanPrimaryKeyIdentifier(PrimaryKeyIdentifier):
    def __init__(
        self, data_documentation_bucket: str, spark=BaseSparkContext.spark
    ) -> None:
        """
        This class identifies the primary keys of the clean table based on the lineage documentation
        and the raw primary keys.
        """

        self.data_documentation_bucket = data_documentation_bucket
        self.data_documentation_volume_path = (
            VolumeMapper().get_volume_path_by_bucket_name(
                self.data_documentation_bucket
            )
        )
        self.spark = spark

    def find_primary_keys(self, schema: str, table_name: str) -> List[str]:
        clean_primary_keys = []
        metadata = self._read_table_metadata(schema, table_name)
        raw_primary_keys = self._find_raw_primary_keys(metadata)
        for raw_primary_key in raw_primary_keys:
            clean_primary_key = self._find_clean_primary_key_from_raw_column(
                raw_primary_key, metadata
            )
            clean_primary_keys.append(clean_primary_key)
        return clean_primary_keys

    def _read_table_metadata(self, schema: str, table_name: str):
        """Returns the metadata of a clean table from the data documentation bucket."""

        try:
            # ".y" in the end of the prefix to include both ".yaml" and ".yml" files
            volume_service = VolumeService()
            lineage_path_pattern = f"metadata/datalake_{schema}_clean/{table_name}.y"
            volume_objects = volume_service.list_objects_by_prefix(
                f"{self.data_documentation_volume_path}/{lineage_path_pattern}"
            )
            object_key = volume_objects[0]
            metadata = yaml.safe_load(volume_service.read_file(object_key))
        except KeyError:
            raise ValueError(
                f"The primary keys of the table {schema}.{table_name} could not be automatically identified, because the metadata file was not found in expected "
                f"path: {self.data_documentation_volume_path}/{lineage_path_pattern}ml. Please, create the lineage file or provide the primary keys manually in DAG Declaration file."
            )
        except yaml.YAMLError:
            raise ValueError(
                f"The primary keys of the table {schema}.{table_name} could not be automatically identified, because "
                f"{self.data_documentation_volume_path}/{object_key} is not a valid YAML file. Please, fix the lineage file or "
                "provide the primary keys manually in DAG Declaration file."
            )

        return metadata

    def _find_raw_primary_keys(self, metadata: dict) -> List[str]:
        """Returns the primary keys of the raw table from the DeltaTable properties."""

        first_column_origin = list(metadata["columns"].values())[0]["lineage"][0]
        raw_table_name = ".".join(first_column_origin.split(".")[:2])
        raw_table = DeltaTable.forName(self.spark, raw_table_name)
        try:
            return raw_table.detail().collect()[0].properties["primary_keys"].split(",")
        except KeyError:
            raise ValueError(
                f"Primary keys of raw table {raw_table_name} not found in DeltaTable properties. Please, provide the primary keys manually in DAG Declaration file."
            )

    def _find_clean_primary_key_from_raw_column(
        self, raw_primary_key: str, metadata: dict
    ) -> str:
        """Returns the clean primary key from the lineage documentation."""

        for clean_column_name, column_metadata in metadata["columns"].items():
            for raw_column_name in column_metadata.get("lineage", []):
                if raw_column_name.lower().endswith(f".{raw_primary_key.lower()}"):
                    return clean_column_name
        raise ValueError(
            f"Primary key {raw_primary_key} not found in lineage documentation. Please, update the lineage file or "
            "provide the primary keys manually in DAG Declaration file."
        )
