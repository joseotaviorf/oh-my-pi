"""File-system list entry compatible with Databricks ``dbutils.fs.ls`` items."""


class FsListEntry:
    """Mimics Databricks ``FileInfo``: ``path``, ``name``, ``isDir()``."""

    __slots__ = ("path", "name", "_is_dir")

    def __init__(self, path: str, name: str, is_dir: bool) -> None:
        self.path = path
        self.name = name
        self._is_dir = is_dir

    def isDir(self) -> bool:
        return self._is_dir
