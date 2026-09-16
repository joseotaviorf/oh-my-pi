class SparkTableStorageFormat:
    JSON = "JSON"
    PARQUET = "PARQUET"
    DEFAULT_RAW = JSON
    DEFAULT_CLEAN = PARQUET
    DEFAULT_CORE = PARQUET
    DEFAULT_ENRICH = PARQUET
    DEFAULT_CLEAN_STAGING = PARQUET
    DEFAULT_DW = PARQUET
    DEFAULT_DW_STAGING = PARQUET
    DEFAULT_METRIC = PARQUET
    DEFAULT_REVERSE = PARQUET
    # Consumption is a query_delta output layer, same as enrich/dw/metric (see
    # LayerEnum.CONSUMPTION, layer_policy_matrix.py). format_options here is
    # informational only for the Delta write path (DeltaTableLoaderPipeline always
    # writes Delta regardless of this value; see its load_and_register log line),
    # but TableLoaderPipeline.run() calls get_storage(self.layer) unconditionally
    # before dispatching, so every valid workflow layer needs an entry here.
    DEFAULT_CONSUMPTION = PARQUET
    # Informational for the Delta write path (see CONSUMPTION), but get_storage()
    # is called for every workflow layer, so an entry is mandatory. INGESTION is
    # not a workflow layer yet (same as TRANSACTIONAL) and is intentionally
    # absent — do not guess a CDC storage format here.
    DEFAULT_TRANSFORMATION = PARQUET

    @classmethod
    def is_valid_storage(cls, storage):
        return storage in cls.get_valid_storages()

    @classmethod
    def get_valid_storages(cls):
        return [
            "raw",
            "clean",
            "core",
            "enrich",
            "clean_staging",
            "dw_staging",
            "dw",
            "metric",
            "reverse",
            "consumption",
            "transformation",
        ]

    @classmethod
    def get_storage(cls, storage):
        if not SparkTableStorageFormat.is_valid_storage(storage):
            raise RuntimeError(
                f"m=get_storage, msg=storage {storage} invalid. Storages allowed are: {', '.join(SparkTableStorageFormat.get_valid_storages())}"
            )
        return {
            "raw": cls.DEFAULT_RAW,
            "clean": cls.DEFAULT_CLEAN,
            "core": cls.DEFAULT_CORE,
            "enrich": cls.DEFAULT_ENRICH,
            "clean_staging": cls.DEFAULT_CLEAN_STAGING,
            "dw_staging": cls.DEFAULT_DW_STAGING,
            "dw": cls.DEFAULT_DW,
            "metric": cls.DEFAULT_METRIC,
            "reverse": cls.DEFAULT_REVERSE,
            "consumption": cls.DEFAULT_CONSUMPTION,
            "transformation": cls.DEFAULT_TRANSFORMATION,
        }.get(storage)
