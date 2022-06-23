from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.metadata_propagator_pipeline import (
    MetadataPropagatorPipeline,
)


class FullContentLineagePipeline(MetadataPropagatorPipeline):
    def __init__(
        self, metadata_propagator_host, database_name, table_name, columns_lineage
    ):
        super(FullContentLineagePipeline, self).__init__(
            metadata_propagator_host,
            database_name,
            table_name,
            MetadataTypeEnum.FULL_CONTENT_LINEAGE,
        )
        self.columns_lineage = columns_lineage

    def build_metadata_propagator_payload(self):
        return [
            {
                "vendor": ["atlas"],
                "database_name": self.database_name,
                "table_name": self.table_name,
                "columns": self.columns_lineage,
            }
        ]
