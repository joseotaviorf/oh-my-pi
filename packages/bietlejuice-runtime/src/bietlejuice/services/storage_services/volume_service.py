import os
from typing import List, Tuple

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.services.storage_services.storage_service import StorageService

logger = QuintoAndarLogger("VolumeService")


class VolumeService(StorageService):
    """Service for operations with Databricks volumes"""

    @logger
    def read_file(self, file_path: str) -> str:
        """Read a file from the volume
        :param file_path: full path to the target volume location, ex: "/Volumes/quintoandar_forno/default/databricks_s3_forno_data_quintoandar_com_br/sql/etl/etl_pipeline.sql"
        :return: file content
        """
        full_path = f"{file_path}"
        with open(full_path, encoding="utf-8") as f:
            return f.read()

    @logger
    def list_objects_by_prefix(self, prefix: str) -> List[str]:
        """List objects in the volume path
        :param path: full path to the target volume location, ex: "/Volumes/quintoandar_forno/default/databricks_s3_forno_data_quintoandar_com_br/sql/etl/etl_pipeline.sql"
        :param prefix: prefix to filter the objects
        :return: list of objects
        """
        files = []
        path, treated_prefix = self._split_volume_path(prefix)
        for file in os.listdir(path):
            if file.startswith(treated_prefix):
                files.append(f"{path}/{file}")
        return files

    def _split_volume_path(self, path: str) -> Tuple[str, str]:
        """Split the volume path into path and prefix
        :param path: full path to the target volume location, ex: "/Volumes/quintoandar_forno/default/databricks_s3_forno_data_quintoandar_com_br/sql/etl/etl_pipeline.sql"
        :return: path and treated prefix
        """
        return "/".join(path.split("/")[:-1]), path.split("/")[-1]

    @logger
    def list_objects(self, path: str, include_size: bool = False):
        """List objects in the volume path
        :param path: full path to the target volume location, ex: "/Volumes/quintoandar_forno/default/databricks_s3_forno_data_quintoandar_com_br/sql/etl/etl_pipeline.sql"
        :param include_size: whether to include the size of the objects
        :return: list of objects
        """
        files = []
        for file in os.listdir(path):
            if include_size:
                files.append((f"{path}/{file}", os.path.getsize(f"{path}/{file}")))
            else:
                files.append(f"{path}/{file}")
        return files
