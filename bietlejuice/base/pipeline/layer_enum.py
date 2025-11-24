from enum import Enum


class LayerEnum(Enum):
    TRANSACTIONAL = "transactional"
    RAW = "raw"
    CLEAN = "clean"
    CLEAN_STAGING = "clean_staging"
    CORE = "core"
    ENRICH = "enrich"
    DW_STAGING = "dw_staging"
    DW = "dw"
    METRIC = "metric"
    REVERSE = "reverse"
    WONKA = "wonka"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
