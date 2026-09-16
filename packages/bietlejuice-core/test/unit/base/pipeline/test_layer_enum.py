from bietlejuice.base.pipeline import LayerEnum


class TestLayerEnum:
    def test_get_available_enum_values(self):
        # act
        returned_value = LayerEnum.get_available_enum_values()

        # assert
        assert list(returned_value) == [
            LayerEnum.TRANSACTIONAL.value,
            LayerEnum.RAW.value,
            LayerEnum.CLEAN.value,
            LayerEnum.CLEAN_STAGING.value,
            LayerEnum.CORE.value,
            LayerEnum.ENRICH.value,
            LayerEnum.DW_STAGING.value,
            LayerEnum.DW.value,
            LayerEnum.METRIC.value,
            LayerEnum.REVERSE.value,
            LayerEnum.QUBE.value,
            LayerEnum.CONSUMPTION.value,
            LayerEnum.WONKA.value,
            LayerEnum.INGESTION.value,
            LayerEnum.TRANSFORMATION.value,
        ]
