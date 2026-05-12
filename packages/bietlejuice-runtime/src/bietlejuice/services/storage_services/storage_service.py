from abc import ABC, abstractmethod
from typing import List


class StorageService(ABC):
    """Abstract class for storage services"""

    @abstractmethod
    def read_file(self, file_path: str) -> str:
        """Read a file from storage
        :param file_path: path to the file
        :return: file content
        """
        pass

    @abstractmethod
    def list_objects(self, folder_path: str, include_size: bool = False):
        """List objects in storage
        :param folder_path: path to the folder
        :param include_size: whether to include the size of the objects
        :return: list of objects
        """
        pass

    @abstractmethod
    def list_objects_by_prefix(self, prefix: str) -> List[str]:
        """List objects in storage by prefix
        :param prefix: prefix to filter the objects
        :return: list of objects
        """
        pass
