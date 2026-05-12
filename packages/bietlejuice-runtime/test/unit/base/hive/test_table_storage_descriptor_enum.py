import pytest

from bietlejuice.base.hive import TableStorageDescriptorEnum


class TestTableStorageDescriptorEnum:
    @pytest.mark.parametrize(
        "layer, expected_return",
        [
            ("raw", TableStorageDescriptorEnum.RAW_FORMAT.value),
            ("clean", TableStorageDescriptorEnum.CLEAN_FORMAT.value),
            ("clean_staging", TableStorageDescriptorEnum.CLEAN_STAGING_FORMAT.value),
            ("core", TableStorageDescriptorEnum.CORE_FORMAT.value),
            ("enrich", TableStorageDescriptorEnum.ENRICH_FORMAT.value),
            ("dw", TableStorageDescriptorEnum.DW.value),
            ("metric", TableStorageDescriptorEnum.METRIC_FORMAT.value),
        ],
    )
    def test_from_layer_with_valid_layer(self, layer, expected_return):
        # act
        returned_value = TableStorageDescriptorEnum.from_layer(layer)

        # assert
        assert returned_value == expected_return
