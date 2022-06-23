from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.metadata_propagator_pipeline import (
    MetadataPropagatorPipeline,
)


class RawLineagePipeline(MetadataPropagatorPipeline):
    def __init__(
        self,
        metadata_propagator_host,
        database_name,
        table_name,
        table_schema,
        product_database_name,
    ):
        super(RawLineagePipeline, self).__init__(
            metadata_propagator_host,
            database_name,
            table_name,
            MetadataTypeEnum.FULL_CONTENT_LINEAGE,
        )
        self.table_schema = table_schema
        self.product_database_name = product_database_name

    def build_metadata_propagator_payload(self):
        payload = {
            "vendor": ["atlas"],
            "database_name": self.database_name,
            "table_name": self.table_name,
            "is_input_from_product": True,
        }
        columns = {}
        for col_name, col_type in self.table_schema.items():
            columns[col_name] = {
                "lineage": [
                    f"{self.product_database_name}.{self.table_name}.{col_name}"
                ]
            }
        payload["columns"] = columns

        return [payload]
