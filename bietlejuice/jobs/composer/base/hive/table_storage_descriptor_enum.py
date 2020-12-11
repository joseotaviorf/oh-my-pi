from enum import Enum

from bietlejuice.jobs.composer.base.hive.table_format_info import TableFormatInfo
from bietlejuice.jobs.composer.base.pipeline import LayerEnum


class TableStorageDescriptorEnum(Enum):
    """
    Maps the file type storage parameter for the Hive Metastore tables
     according to the data lake layers.
    """

    RAW_FORMAT = TableFormatInfo().json
    CLEAN_FORMAT = TableFormatInfo().parquet
    CLEAN_STAGING_FORMAT = TableFormatInfo().parquet
    ENRICH_FORMAT = TableFormatInfo().parquet

    @staticmethod
    def from_layer(layer):
        """
        Gets the table storage descriptor values based on layer value.

        :param layer: one of LayerEnum.valid_values()
        :return: an instance of TableFormatInfo
        :rtype: TableFormatInfo
        """
        LayerEnum.validate_layer(layer)
        return {
            LayerEnum.RAW.value: TableStorageDescriptorEnum.RAW_FORMAT,
            LayerEnum.CLEAN.value: TableStorageDescriptorEnum.CLEAN_FORMAT,
            LayerEnum.CLEAN_STAGING.value: TableStorageDescriptorEnum.CLEAN_STAGING_FORMAT,
            LayerEnum.ENRICH.value: TableStorageDescriptorEnum.ENRICH_FORMAT,
        }.get(layer)
