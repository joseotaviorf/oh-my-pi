class TableStorageFormat:
    JSON = {"format": "ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'"}
    PARQUET = {
        "format": "STORED AS PARQUET",
        "tblproperties": 'tblproperties ("parquet.compress"="SNAPPY")',
    }
    DEFAULT_RAW = JSON
    DEFAULT_CLEAN = PARQUET
    DEFAULT_ENRICH = PARQUET
    DEFAULT_CLEAN_STAGING = PARQUET

    @classmethod
    def is_valid_storage(cls, storage):
        return storage in cls.get_valid_storages()

    @classmethod
    def get_valid_storages(cls):
        return ["raw", "clean", "enrich", "clean_staging"]

    @classmethod
    def get_storage(cls, storage):
        if not TableStorageFormat.is_valid_storage(storage):
            raise RuntimeError(
                "m=get_storage, msg=storage %s invalid. Storages allowed are: %s"
                % (storage, ", ".join(TableStorageFormat.get_valid_storages()))
            )
        return {
            "raw": cls.DEFAULT_RAW,
            "clean": cls.DEFAULT_CLEAN,
            "enrich": cls.DEFAULT_ENRICH,
            "clean_staging": cls.DEFAULT_CLEAN_STAGING,
        }.get(storage)
