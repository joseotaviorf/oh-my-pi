class TableStorageFormat:
    JSON = {
        "format": "ROW FORMAT  serde 'org.apache.hive.hcatalog.data.JsonSerDe'",
        "properties": "",
    }
    PARQUET = {
        "format": "STORED AS PARQUET",
        "properties": 'tblproperties ("parquet.compress"="SNAPPY")',
    }
    DEFAULT_RAW = JSON
    DEFAULT_CLEAN = PARQUET
