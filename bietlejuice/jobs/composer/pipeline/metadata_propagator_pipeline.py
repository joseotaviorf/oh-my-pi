import requests
from quintoandar_logger import QuintoAndarLogger
from requests import RequestException

from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline

logger = QuintoAndarLogger("MetadataPropagatorPipeline")


class MetadataPropagatorPipeline(AbstractPipeline):

    ENDPOINT_MAP = {
        MetadataTypeEnum.FULL_CONTENT_LINEAGE.value: "/fullContentLineage",
        MetadataTypeEnum.QUALITY_METRICS.value: "/qualityMetrics",
        MetadataTypeEnum.LINEAGE.value: "/lineage",
        MetadataTypeEnum.TAGS.value: "/tags",
    }

    def __init__(
        self,
        metadata_propagator_host,
        database_name,
        table_name,
        metadata_type: MetadataTypeEnum,
    ):
        self.metadata_propagator_host = metadata_propagator_host
        self.database_name = database_name
        self.table_name = table_name
        self.endpoint = self.ENDPOINT_MAP[metadata_type.value]

    def build_metadata_propagator_payload(self):
        raise NotImplementedError()

    def run(self):
        payload = self.build_metadata_propagator_payload()
        try:
            response = requests.post(
                f"{self.metadata_propagator_host}{self.endpoint}", json=payload
            )
            response.raise_for_status()
            logger.info(
                f"Metadata sent to metadata-propagator service, payload={payload}, "
                f"response={response}"
            )
        except Exception as e:
            if isinstance(e, RequestException) and e.response is not None:
                raise RequestException(
                    f"Exception trying to call metadata-propagator service, "
                    f"status_code={e.response.status_code}, "
                    f"error_message={e.response.text}"
                )
            else:
                raise Exception(
                    f"Exception trying to call metadata-propagator service, "
                    f"exception={e}"
                )
