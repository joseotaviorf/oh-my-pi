from bietlejuice.jobs.composer.metadata_propagator_pipeline import (
    MetadataPropagatorPipeline,
)


class LineageTagsPipeline(MetadataPropagatorPipeline):
    def build_metadata_propagator_payload(self):
        return [
            {
                "vendor": ["atlas"],
                "database_name": self.database_name,
                "table_name": self.table_name,
            }
        ]
