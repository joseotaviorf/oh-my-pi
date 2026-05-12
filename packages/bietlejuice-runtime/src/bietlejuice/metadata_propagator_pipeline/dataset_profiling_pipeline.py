from datetime import datetime

from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.metadata_propagator_pipeline import MetadataPropagatorPipeline


class DatasetProfilingPipeline(MetadataPropagatorPipeline):
    def __init__(
        self,
        metadata_propagator_host,
        database_name,
        table_name,
        metadata_type: MetadataTypeEnum,
        execution_date,
        profiling_dataset,
    ):
        super().__init__(
            metadata_propagator_host, database_name, table_name, metadata_type
        )
        self.profiling_dataset = profiling_dataset
        self.execution_date = execution_date

    @property
    def quality_check_status(self):
        return "SUCCESS" if len(self.profiling_dataset) > 0 else "FAIL"

    def build_metadata_propagator_payload(self):
        return [
            {
                "vendor": ["datahub"],
                "database_name": self.database_name,
                "table_name": self.table_name,
                "quality_check_status": self.quality_check_status,
                "last_profiling_execution": datetime.strftime(
                    self.execution_date, "%Y-%m-%d"
                ),
                "profiling_dataset": self.profiling_dataset,
            }
        ]
