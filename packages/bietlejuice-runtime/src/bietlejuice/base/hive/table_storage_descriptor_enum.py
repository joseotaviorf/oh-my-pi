from enum import Enum

from bietlejuice.base.hive.table_format_info import TableFormatInfo
from bietlejuice.base.pipeline import LayerEnum


class TableStorageDescriptorEnum(Enum):
    """
    Maps the file type storage parameter for the Hive Metastore tables
     according to the data lake layers.
    """

    RAW_FORMAT = TableFormatInfo().json
    CLEAN_FORMAT = TableFormatInfo().parquet
    CLEAN_STAGING_FORMAT = TableFormatInfo().parquet
    CORE_FORMAT = TableFormatInfo().parquet
    ENRICH_FORMAT = TableFormatInfo().parquet
    DW = TableFormatInfo().parquet
    METRIC_FORMAT = TableFormatInfo().parquet
    TRANSFORMATION_FORMAT = TableFormatInfo().parquet

    @staticmethod
    def from_layer(layer):
        """
        Gets the table storage descriptor values based on layer value.

        :param layer: one of LayerEnum.valid_values()
        :return: an instance of TableFormatInfo
        :rtype: TableFormatInfo
        """
        layer_enum_member = LayerEnum(layer)
        return {
            LayerEnum.RAW: TableStorageDescriptorEnum.RAW_FORMAT.value,
            LayerEnum.CLEAN: TableStorageDescriptorEnum.CLEAN_FORMAT.value,
            LayerEnum.CLEAN_STAGING: TableStorageDescriptorEnum.CLEAN_STAGING_FORMAT.value,
            LayerEnum.CORE: TableStorageDescriptorEnum.CORE_FORMAT.value,
            LayerEnum.ENRICH: TableStorageDescriptorEnum.ENRICH_FORMAT.value,
            LayerEnum.DW: TableStorageDescriptorEnum.DW.value,
            LayerEnum.METRIC: TableStorageDescriptorEnum.METRIC_FORMAT.value,
            LayerEnum.TRANSFORMATION: TableStorageDescriptorEnum.TRANSFORMATION_FORMAT.value,
        }.get(layer_enum_member)
