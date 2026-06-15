"""Stubs for heavy dependencies that must be applied before the test module is imported."""

import os
import sys
from unittest.mock import MagicMock

os.environ.setdefault("PYSPARK_PYTHON", sys.executable)

_STUB_MODULES = [
    "quintoandar_logger",
    "bietlejuice.base.databricks.table_privileges",
    "bietlejuice.base.spark.unity_catalog_helper",
    "bietlejuice.base.spark.base_spark",
    "bietlejuice.clients.db_clients",
    "bietlejuice.loaders.delta_loader",
    "bietlejuice.services.configuration_service",
]
for _mod in _STUB_MODULES:
    sys.modules.setdefault(_mod, MagicMock())


# BaseCoreModelSparkJob is now a base class of the job — we need a real (non-mock)
# class here so Python's class machinery can build the subclass. A flat MagicMock()
# instance cannot be used as a base class.
class _FakeBaseCoreModelSparkJob:
    def __init__(self, job_name: str):
        self.job_name = job_name
        self.logger = MagicMock()
        self.config_service = None

    def initialize_configuration(self, source: str) -> None:
        self.config_service = MagicMock()

    def initialize_spark_session(self):
        return MagicMock()

    def parse_args(self):
        pass

    def create_core_model(self, spark, args):
        pass

    def run_pipeline(self, df, args, spark) -> None:
        pass


_fake_base_module = MagicMock()
_fake_base_module.BaseCoreModelSparkJob = _FakeBaseCoreModelSparkJob
sys.modules.setdefault(
    "bietlejuice.base.spark.base_core_model_spark_job", _fake_base_module
)
