from enum import Enum


class MetadataTypeEnum(Enum):
    FULL_CONTENT_LINEAGE = "full_content_lineage"
    QUALITY_METRICS = "quality_metrics"
    LINEAGE = "lineage"
    TAGS = "tags"
