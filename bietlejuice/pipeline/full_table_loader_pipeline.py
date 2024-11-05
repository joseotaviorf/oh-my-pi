from bietlejuice.base.spark import BaseSparkContext
from bietlejuice.base.spark.unity_catalog_helper import UnityCatalogHelper
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders import SparkMetastoreLoader
from bietlejuice.loaders.s3_loader import S3Loader
from bietlejuice.pipeline.table_loader_pipeline import TableLoaderPipeline
from bietlejuice.services.metastore_services import SparkMetastoreService


class FullTableLoaderPipeline(TableLoaderPipeline):
    def load_and_register(self, df, format_options, **load_options):

        spark_client = SparkClient()

        spark_metastore_service = SparkMetastoreService(spark_client)
        s3_loader = S3Loader()

        if "optimize_dataframe" in load_options:
            optimize_dataframe = load_options.pop("optimize_dataframe")
        else:
            optimize_dataframe = self._should_optimize_dataframe()

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
            optimize_dataframe=optimize_dataframe,
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
            )

        spark_metastore_service.refresh_table(
            self.target_database_name, self.table_name
        )

    def _should_optimize_dataframe(self) -> bool:
        """
        This determines whether S3Loader should run the logic to optimize the number of files in the dataframe before saving or not.
        The optimization heavily affects performance, but reduces the problem with small files.

        However, a study was made indicating that the optimization is not necessary for newer versions of Databricks (12 >), with the exception of
        partitioned tables.
        """
        major, minor = [int(v) for v in BaseSparkContext.spark.version.split(".")[:2]]
        if major < 3 or (major == 3 and minor < 3):
            return True
        if self.partitions:
            return True

        return False
