import logging
from abc import ABC, abstractmethod
from typing import Any, Dict, Generator, List

from bietlejuice.base.api.common.client import BaseAPIClient

LOGGER = logging.getLogger(__name__)


class BasePaginator(ABC):
    """
    Abstract base class for different API pagination strategies.
    """

    def __init__(self, client: BaseAPIClient):
        """
        Initializes the paginator.

        Args:
            client (BaseAPIClient): An instance of BaseAPIClient to make
                                    the requests.
        """
        self.client = client

    @abstractmethod
    def fetch_all(self) -> Generator[List[Dict[str, Any]], None, None]:
        """
        Abstract method that concrete paginators must implement.

        It should fetch all pages of data from the API and yield a list of
        items for each page.
        """
        pass
