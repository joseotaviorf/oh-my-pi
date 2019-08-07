from bietlejuice.jobs.composer.loaders.database_into_datalake_loader import (
    DatabaseIntoDataLakeLoader,
)


class DatabaseIntoDataLakeRawLoader(DatabaseIntoDataLakeLoader):
    def __init__(self, environment, source):
        config = {
            "format": "json",
            "codec": "gzip",
            "datalake_db": "datalake_{}_raw".format(source),
            "datalake_path": "s3://5a-datalake-{}/raw/{}".format(environment, source),
            "create_query_format": "ROW FORMAT serde 'org.apache.hive.hcatalog.data.JsonSerDe'",
        }
        super().__init__(config, environment)
