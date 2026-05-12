from datetime import datetime

from dateutil import parser

from bietlejuice.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.metadata_propagator_pipeline import MetadataPropagatorPipeline


class DatahubQualityMetricsPipeline(MetadataPropagatorPipeline):
    def __init__(
        self,
        metadata_propagator_host,
        database_name,
        table_name,
        metadata_type: MetadataTypeEnum,
        validation_results,
    ):
        super().__init__(
            metadata_propagator_host, database_name, table_name, metadata_type
        )
        self.validation_results = validation_results

    def build_metadata_propagator_payload(self):
        quality_check_status = self.validation_results["metadata"]["suite_result"]
        last_quality_check = parser.parse(
            self.validation_results["metadata"]["run_date"]
        )
        success_rate = self.validation_results["metadata"]["success_rate"]
        quality_checks = self.validation_results["validations"]

        return [
            {
                "vendor": ["datahub"],
                "database_name": self.database_name,
                "table_name": self.table_name,
                "quality_check_status": quality_check_status,
                "last_quality_check": datetime.strftime(
                    last_quality_check, "%Y-%m-%d %H:%M:%S"
                ),
                "success_rate": success_rate,
                "quality_checks": quality_checks,
            }
        ]
