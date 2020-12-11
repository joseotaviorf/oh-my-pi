import pytest

from bietlejuice.jobs.composer.base.hive import TableStorageDescriptorEnum
from bietlejuice.jobs.composer.base.pipeline import LayerEnum


class TestLayerEnum:
    @pytest.mark.parametrize(
        "layer, expected_return",
        [
            ("raw", TableStorageDescriptorEnum.RAW_FORMAT),
            ("clean", TableStorageDescriptorEnum.CLEAN_FORMAT),
            ("clean_staging", TableStorageDescriptorEnum.CLEAN_STAGING_FORMAT),
            ("enrich", TableStorageDescriptorEnum.ENRICH_FORMAT),
        ],
    )
    def test_from_layer_with_valid_layer(self, layer, expected_return):
        # act
        returned_value = TableStorageDescriptorEnum.from_layer(layer)

        # assert
        assert returned_value == expected_return

    def test_from_layer_with_invalid_layer(self):
        # assert
        with pytest.raises(ValueError):
            # act
            LayerEnum.validate_layer("invalid_layer")
