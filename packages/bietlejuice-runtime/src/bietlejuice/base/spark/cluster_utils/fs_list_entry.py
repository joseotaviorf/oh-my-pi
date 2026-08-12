"""File-system list entry compatible with Databricks ``dbutils.fs.ls`` items."""

from typing import NamedTuple


class FsListEntry(NamedTuple):
    """Mirrors Databricks ``FileInfo``: ``path``, ``name``, ``size``, ``modificationTime``.

    A ``NamedTuple`` (not a ``__slots__`` class) so ``spark.createDataFrame(dbutils.fs.ls(...))``
    infers a schema on EMR exactly as it does on Databricks.
    """

    path: str
    name: str
    size: int
    modificationTime: int

    def isDir(self) -> bool:
        # Both listers append "/" to directory names, matching Databricks.
        return self.name.endswith("/")

    def isFile(self) -> bool:
        return not self.isDir()
