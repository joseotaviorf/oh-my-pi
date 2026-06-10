import importlib
import sys

import pytest

from bietlejuice.base.sst.core.utils.collections import get_chunks


@pytest.mark.parametrize(
    "data,max_size,expected",
    [
        ([1, 2, 3, 4], 2, [[1, 2], [3, 4]]),
        ([1, 2, 3], 5, [[1, 2, 3]]),
        ([], 2, []),
        (["a", "b", "c"], 1, [["a"], ["b"], ["c"]]),
    ],
)
def test_get_chunks_partitions_list(data, max_size, expected):
    assert get_chunks(data, max_size) == expected


def test_collections_import_does_not_load_spark_modules():
    """Regression: worker-safe helpers must not pull PySpark driver modules."""
    for module_name in (
        "bietlejuice.base.sst.core.utils.collections",
        "bietlejuice.base.spark",
        "bietlejuice.base.spark.base_spark",
    ):
        sys.modules.pop(module_name, None)

    before = set(sys.modules)
    importlib.import_module("bietlejuice.base.sst.core.utils.collections")
    loaded = set(sys.modules) - before

    assert not any("base.spark" in name for name in loaded)
    assert not any(name.startswith("pyspark") for name in loaded)
