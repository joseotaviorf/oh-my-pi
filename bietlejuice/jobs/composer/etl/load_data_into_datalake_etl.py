from python_logger import QuintoAndarLogger

logger = QuintoAndarLogger()


class LoadDataIntoDatalakeETL:

    PATH = 's3://5a-datalake/temp/ebdb/'

    def load_full_table_into_datalake(self, table, consumer, partition_by=None, concurrency=1):
        raise NotImplementedError()

    def load_incremental_partitioned_table_into_datalake(self, table, query, consumer, partition_by, concurrency=1):
        raise NotImplementedError()

    def get_table_names_and_sizes_from_source(self, consumer):
        raise NotImplementedError()

    def create_raw_external_table(self):
        raise NotImplementedError()

    def get_table_names_from_databricks(self):
        raise NotImplementedError()
