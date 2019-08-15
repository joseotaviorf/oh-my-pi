from bietlejuice.jobs.composer.base.airflow import Environment
from bietlejuice.jobs.composer.loaders.database_into_datalake_loader import (
    DatabaseIntoDataLakeLoader,
)


class DatabaseIntoDataLakeRawLoader(DatabaseIntoDataLakeLoader):
    def __init__(self, environment, source):
        if not Environment.is_valid_environment(environment):
            raise RuntimeError(
                "m=__init__, msg=environment %s is invalid. Environments allowed are: %s"
                % (environment, ", ".join(Environment.get_valid_environments()))
            )
        config = {
            "format": "json",
            "codec": "gzip",
            "datalake_db": "datalake_{}_raw".format(source),
            "datalake_path": "s3://5a-datalake-{}/raw/{}".format(environment, source),
            "create_query_format": "ROW FORMAT serde 'org.apache.hive.hcatalog.data.JsonSerDe'",
        }
        super().__init__(config)
