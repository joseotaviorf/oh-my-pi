from enum import Enum


class LayerEnum(Enum):
    RAW = "raw"
    CLEAN = "clean"
    CLEAN_STAGING = "clean_staging"
    ENRICH = "enrich"
    DW_STAGING = "dw_staging"
    DW = "dw"

    @classmethod
    def is_layer_valid(cls, layer):
        return layer in cls.__members__.values()
