from bietlejuice.base.spark import BaseSparkContext
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.pipeline.abstract_pipeline import AbstractPipeline


class DeltaDefaultRowAdditionPipeline(AbstractPipeline):
    """
    Pipeline responsible for adding a default row with sk = -1 to a Delta dim table.
    """

    def __init__(
        self,
        database_name: str,
        table_name: str,
        database_location: str,
        spark=BaseSparkContext.spark,
    ) -> None:
        """
        :param database_name: database name for the table to be processed
        :param table_name: name of the table to be processed, without the schema
        :param database_location: database location in S3
        """
        self.database_name = database_name
        self.table_name = table_name
        self.database_location = database_location
        self.full_table_name = f"{self.database_name}.{self.table_name}"
        self.spark = spark

    def run(self):
        if not self.is_dim():
            return
        default_row = self.generate_default_row()
        self.merge_default_row(default_row)

    def is_dim(self):
        return self.table_name.startswith("dim_")

    def generate_default_row(self):
        schema = self.spark.table(self.full_table_name).schema
        sk_col_name = schema[0].name
        return self.spark.createDataFrame(data=[{sk_col_name: -1}], schema=schema)

    def merge_default_row(self, default_row_df):
        loader = DeltaLoader(self.spark)
        loader.load_table(
            table_name=self.full_table_name,
            path=f"{self.database_location}/{self.table_name}",
            source_df=default_row_df,
            merge_on=[default_row_df.columns[0]],
            when_matched_update_condition="FALSE",  # This way, we don't overwrite if it already exists
        )
