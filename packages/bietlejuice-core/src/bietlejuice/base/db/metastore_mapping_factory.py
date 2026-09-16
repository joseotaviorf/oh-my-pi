from bietlejuice.base.db.datalake_metastore_mapping import DatalakeMetastoreMapping
from bietlejuice.base.db.dw_metastore_mapping import DwMetastoreMapping
from bietlejuice.base.db.metastore_mapping import MetastoreMapping
from bietlejuice.base.db.metric_metastore_mapping import MetricMetastoreMapping
from bietlejuice.base.db.qube_metastore_mapping import QubeMetastoreMapping
from bietlejuice.base.db.reverse_metastore_mapping import ReverseMetastoreMapping
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class MetastoreMappingFactory:
    """ "Returns the correct Metastore Mapper according to the desired layer"""

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
            LayerEnum.QUBE: QubeMetastoreMapping,
            LayerEnum.WONKA: DatalakeMetastoreMapping,
            LayerEnum.CONSUMPTION: DatalakeMetastoreMapping,
            LayerEnum.TRANSFORMATION: DatalakeMetastoreMapping,
        }[layer](source, bucket)
