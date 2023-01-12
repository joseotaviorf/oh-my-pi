from enum import Enum


class LayerEnum(Enum):
    RAW = "raw"
    CLEAN = "clean"
    CLEAN_STAGING = "clean_staging"
    ENRICH = "enrich"
    DW_STAGING = "dw_staging"
    DW = "dw"
    METRIC = "metric"
    REVERSE = "reverse"

    @classmethod
    def is_layer_valid(cls, layer):
        """
        Check if layer is one of the enum keys (not the values)

        :param layer: the layer key to be checked
        :return: bool
        """
        return layer in cls.__members__.values()

    @staticmethod
    def validate_layer(layer: str):
        """
        Checks if a layer is one of the enum layers values.

        :param layer: the layer enum value
        :type layer: str
        :rtype: bool
        :raises: ValueError
        """
        valid_values = LayerEnum.get_available_enum_values()
        if layer not in valid_values:
            raise ValueError(
                "m=validate_layer, msg=The layer is not valid, "
                f"given_layer={layer}, valid_layers={valid_values}"
            )
        return True

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
