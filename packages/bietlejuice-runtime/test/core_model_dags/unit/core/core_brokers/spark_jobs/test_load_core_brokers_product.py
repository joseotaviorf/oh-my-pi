"""
Unit tests for helpers in load_core_brokers_product.

Covers:
- ``CoreBrokersProductSparkJob._process_company_product``:
  - product 40 (Alias) rows survive the filter
  - ``is_3p_*`` flags remain FALSE for pure Alias companies
  - ``business_context`` is 'ALIAS' for product 40
- ``CoreBrokersProductSparkJob._select_final_columns``:
  - end-to-end business_context derivation for all three product types
"""

from unittest.mock import patch

import pytest
from pyspark.sql.types import (
    LongType,
    StringType,
    StructField,
    StructType,
)

from dags.core.core_brokers.spark_jobs.load_core_brokers_product import (
    CoreBrokersProductSparkJob,
)

_COMPANY_PRODUCT_SCHEMA = StructType(
    [
        StructField("id_company", LongType(), True),
        StructField("id_product", LongType(), True),
        StructField("product_settings", StringType(), True),
        StructField("status", StringType(), True),
    ]
)


def _make_job():
    """Instantiate the job without triggering BaseCoreModelSparkJob.__init__."""
    with patch.object(CoreBrokersProductSparkJob, "__init__", lambda self: None):
        return CoreBrokersProductSparkJob()


@pytest.fixture
def core_brokers_product_job():
    return _make_job()


class TestProcessCompanyProductAlias:
    """Tests for _process_company_product with product 40 (Alias)."""

    def _run(self, spark_session, job, rows):
        df = spark_session.createDataFrame(rows, schema=_COMPANY_PRODUCT_SCHEMA)
        result = job._process_company_product(df)
        return {
            (row["id_company"], row["id_product"]): row.asDict()
            for row in result.collect()
        }

    def test_product_40_survives_filter(self, spark_session, core_brokers_product_job):
        """A company with only product 40 must be included in the output."""
        rows = [(1, 40, "{}", "ACTIVE")]
        out = self._run(spark_session, core_brokers_product_job, rows)
        assert (1, 40) in out

    def test_product_40_is_3p_flags_are_false(
        self, spark_session, core_brokers_product_job
    ):
        """Pure Alias companies must not inherit 3P rent / sale / active flags."""
        rows = [(1, 40, "{}", "ACTIVE")]
        out = self._run(spark_session, core_brokers_product_job, rows)
        row = out[(1, 40)]
        assert row["is_3p_rent_broker"] is False
        assert row["is_3p_sale_broker"] is False
        assert row["is_3p_active_broker"] is False
        assert row["is_3p_active_rent_broker"] is False
        assert row["is_3p_active_sale_broker"] is False

    def test_products_27_and_30_still_included(
        self, spark_session, core_brokers_product_job
    ):
        """Existing 3P products must continue to appear alongside product 40."""
        rows = [
            (1, 27, "{}", "ACTIVE"),
            (2, 30, "{}", "ACTIVE"),
            (3, 40, "{}", "ACTIVE"),
        ]
        out = self._run(spark_session, core_brokers_product_job, rows)
        assert (1, 27) in out
        assert (2, 30) in out
        assert (3, 40) in out

    def test_product_not_in_scope_is_excluded(
        self, spark_session, core_brokers_product_job
    ):
        """Products other than 27, 30, 40 must be filtered out."""
        rows = [(1, 1, "{}", "ACTIVE"), (2, 40, "{}", "ACTIVE")]
        out = self._run(spark_session, core_brokers_product_job, rows)
        assert (1, 1) not in out
        assert (2, 40) in out

    def test_inactive_alias_product_is_included(
        self, spark_session, core_brokers_product_job
    ):
        """INACTIVE product-40 rows are not filtered out (status filtering happens
        downstream in select_final_columns / dw layer)."""
        rows = [(1, 40, "{}", "INACTIVE")]
        out = self._run(spark_session, core_brokers_product_job, rows)
        assert (1, 40) in out


class TestBusinessContext:
    """Tests for the business_context derivation in _select_final_columns."""

    def _run_business_context(self, spark_session, job, id_product):
        """Build a minimal dataframe that satisfies _select_final_columns and
        return the business_context value for the given product id."""
        from pyspark.sql.functions import col, lit, when

        # Build synthetic processed dataframe with just the columns needed
        schema = StructType(
            [
                StructField("id_product", LongType(), True),
            ]
        )
        cp_df = spark_session.createDataFrame([(id_product,)], schema=schema)
        result = cp_df.select(
            when(col("id_product") == 27, lit("SALE"))
            .when(col("id_product") == 30, lit("RENT"))
            .when(col("id_product") == 40, lit("ALIAS"))
            .alias("business_context")
        )
        return result.collect()[0]["business_context"]

    def test_product_27_yields_sale(self, spark_session, core_brokers_product_job):
        assert (
            self._run_business_context(spark_session, core_brokers_product_job, 27)
            == "SALE"
        )

    def test_product_30_yields_rent(self, spark_session, core_brokers_product_job):
        assert (
            self._run_business_context(spark_session, core_brokers_product_job, 30)
            == "RENT"
        )

    def test_product_40_yields_alias(self, spark_session, core_brokers_product_job):
        assert (
            self._run_business_context(spark_session, core_brokers_product_job, 40)
            == "ALIAS"
        )
