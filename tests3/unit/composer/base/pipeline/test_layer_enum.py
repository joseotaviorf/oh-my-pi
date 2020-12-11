import pytest

from bietlejuice.jobs.composer.base.pipeline import LayerEnum


class TestLayerEnum:
    @pytest.mark.parametrize(
        "layer, expected_return",
        [
            (LayerEnum.RAW, True),
            (LayerEnum.CLEAN, True),
            (LayerEnum.CLEAN_STAGING, True),
            (LayerEnum.ENRICH, True),
            (LayerEnum.DW_STAGING, True),
            (LayerEnum.DW, True),
            ("some wrong key", False),
        ],
    )
    def test_is_layer_valid(self, layer, expected_return):
        # act
        returned_value = LayerEnum.is_layer_valid(layer)

        # assert
        assert returned_value == expected_return

    def test_get_valid_values(self):
        # act
        returned_value = LayerEnum.get_valid_values()

        # assert
        assert list(returned_value) == [
            LayerEnum.RAW.value,
            LayerEnum.CLEAN.value,
            LayerEnum.CLEAN_STAGING.value,
            LayerEnum.ENRICH.value,
            LayerEnum.DW_STAGING.value,
            LayerEnum.DW.value,
        ]

    @pytest.mark.parametrize(
        "layer, expected_return",
        [
            ("raw", True),
            ("clean", True),
            ("clean_staging", True),
            ("enrich", True),
            ("dw_staging", True),
            ("dw", True),
        ],
    )
    def test_validate_layer_for_valid_value(self, layer, expected_return):
        # act
        returned_value = LayerEnum.validate_layer(layer)

        # assert
        assert returned_value == expected_return

    def test_validate_layer_for_invalid_value(self):
        # assert
        with pytest.raises(ValueError):
            # act
            LayerEnum.validate_layer("invalid_layer")
