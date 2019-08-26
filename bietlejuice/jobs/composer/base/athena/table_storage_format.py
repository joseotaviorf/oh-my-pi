class TableStorageFormat:
    JSON = {
        "format": "ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'",
        "properties": "",
    }
    PARQUET = {
        "format": "STORED AS PARQUET",
        "properties": 'tblproperties ("parquet.compress"="SNAPPY")',
    }
    DEFAULT_RAW = JSON
    DEFAULT_CLEAN = PARQUET
