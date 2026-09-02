"""Spark session and module mocks for load_vocs_machina_meta_raw tests.

Same convention as
test/dags/mlops/evidently_ml_monitor/spark_jobs/conftest.py: the job's
bietlejuice/quintoandar_logger imports aren't installable in this test
environment, so they are stubbed with MagicMock before the job module is
imported. A real local SparkSession is provided (not mocked) so tests can
assert on actual inferred/enforced schemas and column values -- this job's
behavior (explicit StructType enforcement, explode, regex-based run_id
extraction) needs a real Spark to verify meaningfully.

NOTE (known cross-file conflict within this `unit-tests-dags` domain): this
file lives under `for_rent` alongside
`vocs_machina_planning/spark_jobs/test_load_vocs_machina_inference_status_raw.py`,
which stubs `sys.modules["pyspark"]`/`["pyspark.sql"]` with `MagicMock()` at
module import time. `unit-tests-dags` runs every `test/dags/<domain>/`
directory in one shared pytest process (see the Makefile's
`_run_dag_suite`), and since pytest fully collects (imports) every test
module in a domain before running any test, that stubbing clobbers the real
pyspark modules for the rest of the process regardless of file/test
execution order -- breaking this suite's real-Spark tests when run as part
of the whole `for_rent` domain (though not when run in isolation, e.g.
`pytest test/dags/for_rent/vocs_machina_meta`). `mlops` and `tech_platform`
already hit this same class of problem and are special-cased in the
Makefile to run each of their nested job dirs as a separate pytest process;
`for_rent` is now special-cased the same way so this suite and
`vocs_machina_planning` do not share a pytest process.
"""

import sys
from unittest.mock import MagicMock

import pytest

_BIETLEJUICE_MOCKS = [
    "bietlejuice",
    "bietlejuice.base",
    "bietlejuice.base.db",
    "bietlejuice.base.validation",
    "bietlejuice.base.validation.spark_args",
    "bietlejuice.clients",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services",
    "bietlejuice.services.metastore_services",
    "quintoandar_logger",
]
for _mod in _BIETLEJUICE_MOCKS:
    sys.modules.setdefault(_mod, MagicMock())


@pytest.fixture(scope="session")
def spark():
    pytest.importorskip("pyspark")
    from pyspark.sql import SparkSession

    session = (
        SparkSession.builder.appName("test_load_vocs_machina_meta_raw")
        .master("local[1]")
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.driver.bindAddress", "127.0.0.1")
        .config("spark.ui.enabled", "false")
        .getOrCreate()
    )
    yield session
    session.stop()
