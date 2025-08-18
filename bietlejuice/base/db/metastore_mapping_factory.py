from bietlejuice.base.db import (
    MetastoreMapping,
    DatalakeMetastoreMapping,
    DwMetastoreMapping,
    ReverseMetastoreMapping,
    MetricMetastoreMapping,
)
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class MetastoreMappingFactory:
    """"Returns the correct Metastore Mapper according to the desired layer"""

    @staticmethod
    def get_mapper_by_layer(
        layer: LayerEnum, source: str, bucket: str
    ) -> MetastoreMapping:
        return {
            LayerEnum.TRANSACTIONAL: DatalakeMetastoreMapping,
            LayerEnum.RAW: DatalakeMetastoreMapping,
            LayerEnum.CLEAN: DatalakeMetastoreMapping,
            LayerEnum.CLEAN_STAGING: DatalakeMetastoreMapping,
            LayerEnum.CORE: DatalakeMetastoreMapping,
            LayerEnum.ENRICH: DatalakeMetastoreMapping,
            LayerEnum.DW: DwMetastoreMapping,
            LayerEnum.DW_STAGING: DwMetastoreMapping,
            LayerEnum.METRIC: MetricMetastoreMapping,
            LayerEnum.REVERSE: ReverseMetastoreMapping,
        }[layer](source, bucket)
