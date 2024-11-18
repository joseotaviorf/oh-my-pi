from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.pipeline.table_loader_pipeline import TableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper


class IncrementalTableLoaderPipeline(TableLoaderPipeline):
    def load_and_register(
        self, df, format_options, force_recreate=False, **load_options
    ):

        spark_client = SparkClient()

        spark_metastore_service = SparkMetastoreService(spark_client)
        s3_loader = S3Loader()

        save_to_unity_catalog = UnityCatalogHelper.is_default_catalog_using_unity()
        if save_to_unity_catalog:
            # With unity Catalog, we're supposed to save directly as table, not save the files and update
            # the metastore separately
            load_options[
                "full_table_name"
            ] = f"{self.target_database_name}.{self.table_name}"

        s3_loader.load_df(
            df=df,
            format_options=format_options,
            s3_path=self.target_database_location + self.table_name,
            partitions=self.partitions,
            **load_options,
        )

        if not save_to_unity_catalog:
            # Again, if we're using Unity Catalog, the metastore will already have been updated when saving the table
            spark_metastore_loader = SparkMetastoreLoader(spark_metastore_service)
            spark_metastore_loader.update_metastore(
                df=df,
                database_name=self.target_database_name,
                table_name=self.table_name,
                format_options=format_options,
                database_location=self.target_database_location,
                partitions=self.partitions,
                force_recreate=force_recreate,
            )

            if self.partitions:
                spark_metastore_service.create_new_partitions_from_df(
                    df=df,
                    database_name=self.target_database_name,
                    table_name=self.table_name,
                    partition_cols=self.partitions,
                )

        spark_metastore_service.refresh_table(
            self.target_database_name, self.table_name
        )

        if (
            self.table_privileges
            and UnityCatalogHelper.is_cluster_unity_catalog_enabled()
        ):
            self.table_privileges.apply()
