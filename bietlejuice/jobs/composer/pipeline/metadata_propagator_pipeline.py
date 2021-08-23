import requests
from quintoandar_logger import QuintoAndarLogger
from requests import RequestException

from bietlejuice.jobs.composer.base.pipeline.metadata_type_enum import MetadataTypeEnum
from bietlejuice.jobs.composer.pipeline.abstract_pipeline import AbstractPipeline

logger = QuintoAndarLogger("MetadataPropagatorPipeline")


class MetadataPropagatorPipeline(AbstractPipeline):

    ENDPOINT_MAP = {
        MetadataTypeEnum.LINEAGE.value: "/lineage",
        MetadataTypeEnum.LINEAGE_FROM_PRODUCT.value: "/lineageFromProduct",
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
        except RequestException as exception:
            if exception.response is not None:
                logger.error(
                    f"Exception trying to call metadata-propagator service, "
                    f"status_code={exception.response.status_code}, "
                    f"error_message={exception.response.text}"
                )
            else:
                logger.error(
                    f"Exception trying to call metadata-propagator service, "
                    f"exception={exception}"
                )
