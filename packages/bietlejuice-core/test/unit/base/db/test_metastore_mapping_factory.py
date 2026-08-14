from bietlejuice.base.db.datalake_metastore_mapping import DatalakeMetastoreMapping
from bietlejuice.base.db.metastore_mapping_factory import MetastoreMappingFactory
from bietlejuice.base.pipeline.layer_enum import LayerEnum


class TestMetastoreMappingFactory:
    def test_consumption_layer_uses_datalake_mapper(self):
        mapper = MetastoreMappingFactory.get_mapper_by_layer(
            layer=LayerEnum.CONSUMPTION,
            source="bi_metrics",
            bucket="bucket-forno",
        )

        assert isinstance(mapper, DatalakeMetastoreMapping)
        assert mapper.get_full_database_name(LayerEnum.CONSUMPTION) == "bi_metrics"
