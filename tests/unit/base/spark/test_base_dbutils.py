import unittest
from bietlejuice.base.spark.base_spark import BaseDBUtils


class DBUtilsMock:
    def __init__(self, files: list) -> None:
        self.fs = FSMock(files)


class FSMock:
    """
    Mock for the DBUtils.fs object.
    Simulates a file system with a list of files.
    """

    def __init__(self, files: list) -> None:
        self.files = [f.replace("//", "/") for f in files]

    def ls(self, path):
        path = path.replace("//", "/")
        if path[-1] != "/":
            path += "/"
        resulting_files = []
        for file in self.files:
            if file.startswith(path):
                subpaths = file[len(path) :].split("/")
                name = subpaths[0] + ("/" if len(subpaths) > 1 else "")
                resulting_files.append(FSObjectMock(name))
        return resulting_files


class FSObjectMock:
    def __init__(self, name: str) -> None:
        self.name = name

    def isDir(self):
        return self.name.endswith("/")


class TestBaseDBUtils(unittest.TestCase):
    def test_discover_partition_values_in_path_without_max_recursive_depth(self):
        dbutils = DBUtilsMock(
            [
                "s3://bucket/table/partition1=a/partition2=d/file.parquet",
                "s3://bucket/table/partition1=b/partition2=e/file.parquet",
                "s3://bucket/table/partition1=c/partition2=f/file.parquet",
            ]
        )
        base_db_utils = BaseDBUtils()
        result = base_db_utils.discover_partition_values_in_path(
            "s3://bucket/table/", dbutils
        )
        self.assertEqual(result, [["a", "d"], ["b", "e"], ["c", "f"]])

    def test_discover_partition_values_in_path_with_max_recursive_depth(self):
        dbutils = DBUtilsMock(
            [
                "s3://bucket/table/partition1=a/partition2=d/file.parquet",
                "s3://bucket/table/partition1=b/partition2=e/file.parquet",
                "s3://bucket/table/partition1=c/partition2=f/file.parquet",
            ]
        )
        base_db_utils = BaseDBUtils()
        result = base_db_utils.discover_partition_values_in_path(
            "s3://bucket/table/", dbutils, max_recursive_depth=1
        )
        self.assertEqual(result, [["a"], ["b"], ["c"]])
