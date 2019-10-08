class TableStorageFormat:
    JSON = {"format": "ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'"}
    PARQUET = {
        "format": "STORED AS PARQUET",
        "tblproperties": 'tblproperties ("parquet.compress"="SNAPPY")',
    }
    DEFAULT_RAW = JSON
    DEFAULT_CLEAN = PARQUET
