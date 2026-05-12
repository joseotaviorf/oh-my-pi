from typing import Dict

from hierarchical_conf.hierarchical_conf import HierarchicalConf
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.paths import BIETLEJUICE_CONFIG_ROOT

logger = QuintoAndarLogger("VolumeMapper")


class VolumeMapper:
    """Class responsible for managing mappings between buckets and volumes"""

    volume_mapping = {
        "databricks_bucket": "volume_databricks_bucket",
        "data_documentation_bucket": "volume_data_documentation_bucket",
    }

    def __init__(self):
        self._global_confs = HierarchicalConf([BIETLEJUICE_CONFIG_ROOT])

    def get_bucket_mapping(self) -> Dict[str, str]:
        """
        Map of bucket names to volume paths
        :return: dictionary mapping bucket names to volume paths
        """
        mapping = {}
        for bucket_name, volume_path in self.volume_mapping.items():
            mapping[self._global_confs.get_config(bucket_name)] = (
                self._global_confs.get_config(volume_path)
            )
        return mapping

    def get_volume_path_by_bucket_name(self, bucket_name: str) -> str:
        """
        Get the volume path based on the bucket name
        :param bucket_name: bucket name
        :return: volume path
        :raises KeyError: if the bucket is not found
        """
        bucket_mapping = self.get_bucket_mapping()
        if bucket_name not in bucket_mapping:
            available_buckets = list(bucket_mapping.keys())
            raise KeyError(
                f"Bucket '{bucket_name}' not found. Available buckets: {available_buckets}"
            )
        return bucket_mapping[bucket_name]

    def get_volume_path_by_config(self, bucket_name_config: str) -> str:
        """
        Get the volume path based on the bucket configuration
        :param bucket_name_config: bucket configuration
        :return: volume path
        :raises KeyError: if the configuration is not found
        """
        config_mapping = self.volume_mapping
        if bucket_name_config not in config_mapping:
            available_configs = list(config_mapping.keys())
            raise KeyError(
                f"Bucket config '{bucket_name_config}' not found. Available configs: {available_configs}"
            )

        volume_config = config_mapping[bucket_name_config]
        return self._global_confs.get_config(volume_config)

    def list_available_buckets(self) -> list:
        """
        List all available buckets
        :return: list of bucket names
        """
        return list(self.get_bucket_mapping().keys())

    def list_available_configs(self) -> list:
        """
        List all available bucket configurations
        :return: list of bucket configurations
        """
        return list(self.volume_mapping.keys())
