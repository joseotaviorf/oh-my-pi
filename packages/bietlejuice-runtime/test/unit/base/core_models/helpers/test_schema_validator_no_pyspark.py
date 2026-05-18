"""
Verifies that schema_validator degrades gracefully when PySpark is absent.

The try/except ImportError guard in schema_validator.py is intentional — the
file is assigned to the core package and must be importable without PySpark
installed (e.g. in the Airflow scheduler or the compiler environment).

This test anchors that design decision by simulating a missing pyspark
installation and confirming the module loads cleanly with PYSPARK_AVAILABLE=False.
"""

import sys


class TestSchemaValidatorWithoutPySpark:
    def test_module_imports_cleanly_without_pyspark(self, monkeypatch):
        sv_module_key = "bietlejuice.base.core_models.helpers.schema_validator"

        # Simulate pyspark being absent: setting a key to None in sys.modules
        # causes any `import pyspark.*` to raise ImportError.
        monkeypatch.setitem(sys.modules, "pyspark", None)
        monkeypatch.setitem(sys.modules, "pyspark.sql", None)
        monkeypatch.setitem(sys.modules, "pyspark.sql.types", None)

        # Remove the cached module so it is re-evaluated under the patched state.
        # monkeypatch restores the original entry on teardown.
        monkeypatch.delitem(sys.modules, sv_module_key, raising=False)

        import bietlejuice.base.core_models.helpers.schema_validator as sv_no_spark

        assert sv_no_spark.PYSPARK_AVAILABLE is False, (
            "PYSPARK_AVAILABLE must be False when pyspark is not installed"
        )
        assert sv_no_spark.DataFrame is None, (
            "DataFrame must be None when pyspark is not installed"
        )
        assert sv_no_spark.DataType is None, (
            "DataType must be None when pyspark is not installed"
        )

    def test_schema_validator_can_be_instantiated_without_pyspark(self, monkeypatch):
        sv_module_key = "bietlejuice.base.core_models.helpers.schema_validator"

        monkeypatch.setitem(sys.modules, "pyspark", None)
        monkeypatch.setitem(sys.modules, "pyspark.sql", None)
        monkeypatch.setitem(sys.modules, "pyspark.sql.types", None)
        monkeypatch.delitem(sys.modules, sv_module_key, raising=False)

        import bietlejuice.base.core_models.helpers.schema_validator as sv_no_spark

        validator = sv_no_spark.SchemaValidator()
        assert validator is not None
        assert validator.PYSPARK_AVAILABLE is False

    def test_pure_python_type_constants_are_accessible_without_pyspark(
        self, monkeypatch
    ):
        sv_module_key = "bietlejuice.base.core_models.helpers.schema_validator"

        monkeypatch.setitem(sys.modules, "pyspark", None)
        monkeypatch.setitem(sys.modules, "pyspark.sql", None)
        monkeypatch.setitem(sys.modules, "pyspark.sql.types", None)
        monkeypatch.delitem(sys.modules, sv_module_key, raising=False)

        import bietlejuice.base.core_models.helpers.schema_validator as sv_no_spark

        assert isinstance(sv_no_spark.SchemaValidator.VALID_SCHEMA_TYPES, list)
        assert len(sv_no_spark.SchemaValidator.VALID_SCHEMA_TYPES) > 0
        assert isinstance(sv_no_spark.SchemaValidator.TYPE_TO_SPARK_MAPPING, dict)
        assert isinstance(sv_no_spark.SchemaValidator.SPARK_TO_TYPE_MAPPING, dict)
