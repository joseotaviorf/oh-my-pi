from bietlejuice.jobs.composer.clients.db_clients import SparkClient
from bietlejuice.jobs.composer.loaders import SparkMetastoreLoader
from bietlejuice.jobs.composer.loaders.s3_loader import S3Loader
from bietlejuice.jobs.composer.pipeline.table_loader_pipeline import TableLoaderPipeline
from bietlejuice.jobs.composer.services.metastore_services import SparkMetastoreService


class IncrementalTableLoaderPipeline(TableLoaderPipeline):
    def load_and_register(self, df, format_options):

        spark_client = SparkClient()

        spark_metastore_service = SparkMetastoreService(spark_client)
        s3_loader = S3Loader()

        s3_loader.load_df(
            df=df,
            format_options=format_options,
            s3_path=self.target_database_location + self.table_name,
            partitions=self.partitions,
        )

        spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
        spark_metastore_loader.update_metastore(
            df=df,
            database_name=self.target_database_name,
            table_name=self.table_name,
            format_options=format_options,
            database_location=self.target_database_location,
            partitions=self.partitions,
            force_recreate=False,
        )

        spark_metastore_service.create_new_partitions_from_df(
            df=df,
            database_name=self.target_database_name,
            table_name=self.table_name,
            partition_cols=self.partitions,
        )

        spark_metastore_service.refresh_table(
            self.target_database_name, self.table_name
        )
