"""
Pagination module for handling various API pagination strategies.

This module provides a collection of paginator classes that implement
different pagination patterns commonly found in REST APIs.
"""

from bietlejuice.base.api.pagination.base import BasePaginator
from bietlejuice.base.api.pagination.cursor import CursorPaginator
from bietlejuice.base.api.pagination.header_link import HeaderLinkPaginator
from bietlejuice.base.api.pagination.offset_limit import OffsetLimitPaginator
from bietlejuice.base.api.pagination.page_per_page import PagePerPagePaginator

__all__ = [
    "BasePaginator",
    "CursorPaginator",
    "HeaderLinkPaginator",
    "OffsetLimitPaginator",
    "PagePerPagePaginator",
]
