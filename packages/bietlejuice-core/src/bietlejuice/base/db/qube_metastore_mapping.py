import re

from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class QubeMetastoreMapping(MetastoreMapping):
    """QUBE properties mapping for Hive Metastore."""

    DATABASE_PATTERN = re.compile(r"^qube_(?P<type>dimensions|measures|metrics)$")

    def get_full_database_name(self, layer: LayerEnum = None) -> str:
        """
        Returns the full database name for QUBE tables.

        The source parameter should be "dimensions", "measures", or "metrics".
        Returns "qube_dimensions", "qube_measures", or "qube_metrics".
        """
        if self.source not in ["dimensions", "measures", "metrics"]:
            # Fallback: try to infer from source name pattern
            if "dimension" in self.source:
                subdirectory = "dimensions"
            elif "measure" in self.source:
                subdirectory = "measures"
            elif "metric" in self.source:
                subdirectory = "metrics"
            else:
                raise ValueError(
                    f"Invalid QUBE source '{self.source}'. Must be 'dimensions', 'measures', or 'metrics'"
                )
        else:
            subdirectory = self.source

        return f"qube_{subdirectory}"

    def get_full_database_path(self, layer: LayerEnum = None):
        """
        Returns the full S3 path for QUBE tables.

        Path pattern: s3a://{bucket}/qube/{dimensions|measures|metrics}
        Note: Does not include trailing slash to avoid double slashes when constructing table paths.
        """
        if self.source not in ["dimensions", "measures", "metrics"]:
            # Fallback: try to infer from source name pattern
            if "dimension" in self.source:
                subdirectory = "dimensions"
            elif "measure" in self.source:
                subdirectory = "measures"
            elif "metric" in self.source:
                subdirectory = "metrics"
            else:
                raise ValueError(
                    f"Invalid QUBE source '{self.source}'. Must be 'dimensions', 'measures', or 'metrics'"
                )
        else:
            subdirectory = self.source

        return f"s3a://{self.bucket}/qube/{subdirectory}"
