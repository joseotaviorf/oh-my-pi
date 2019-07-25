from bietlejuice.jobs.composer.loaders.database_into_datalake_loader import (
    DatabaseIntoDataLakeLoader,
)


class DatabaseIntoDataLakeRawLoader(DatabaseIntoDataLakeLoader):
    def __init__(self):
        config = {
            "format": "json",
            "codec": "gzip",
            "datalake_db": "datalake_raw_spark",
            "datalake_path": "s3://5a-datalake/raw_spark",
            "create_query_format": "ROW FORMAT serde 'org.apache.hive.hcatalog.data.JsonSerDe'",
        }
        super().__init__(config)
