from enum import Enum


class StorageFormatEnum(Enum):
    JSON = "json"
    PARQUET = "parquet"
    DELTA = "delta"
