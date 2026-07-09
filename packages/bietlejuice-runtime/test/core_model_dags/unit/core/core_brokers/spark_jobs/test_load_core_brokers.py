"""
Unit tests for helpers in load_core_brokers.

Covers:
- ``_broker_string_tag``: accent / whitespace stripping.
- ``CoreBrokersSparkJob._extract_latest_document_number`` and
  ``CoreBrokersSparkJob._process_company_document``: pivoting CRECI / CNPJ /
  RFC per company by picking the most recent document (max ``ts_updated``)
  regardless of ``document.status``.
"""

from datetime import datetime
from types import SimpleNamespace
from unittest.mock import patch

import pytest
from pyspark.sql.functions import col
from pyspark.sql.types import (
    LongType,
    StringType,
    StructField,
    StructType,
    TimestampType,
)

from dags.core.core_brokers.spark_jobs.load_core_brokers import (
    CoreBrokersSparkJob,
    _broker_string_tag,
)


class TestBrokerStringTag:
    """Tests for _broker_string_tag (accent strip + whitespace removal, case preserved)."""

    @pytest.mark.parametrize(
        "raw,expected",
        [
            ("Imóveis  Central", "ImoveisCentral"),
            ("SÃO  PAULO", "SAOPAULO"),
            ("José da Silva", "JosedaSilva"),
            ("NoAccents Here", "NoAccentsHere"),
            ("", ""),
            ("   ", ""),
            ("Ção", "Cao"),
            ("MixedCase ÁÉÍ", "MixedCaseAEI"),
        ],
    )
    def test_strips_accents_and_whitespace_preserves_case(
        self, spark_session, raw, expected
    ):
        df = spark_session.createDataFrame([(raw,)], ["name"])
        out = df.select(_broker_string_tag(col("name")).alias("tag")).collect()[0][
            "tag"
        ]
        assert out == expected

    def test_null_input_yields_null(self, spark_session):
        schema = StructType([StructField("name", StringType(), True)])
        df = spark_session.createDataFrame([(None,)], schema=schema)
        out = df.select(_broker_string_tag(col("name")).alias("tag")).collect()[0][
            "tag"
        ]
        assert out is None


_COMPANY_DOCUMENT_SCHEMA = StructType(
    [
        StructField("id_company", LongType(), True),
        StructField("id_document", LongType(), True),
    ]
)

_DOCUMENT_SCHEMA = StructType(
    [
        StructField("id", LongType(), True),
        StructField("document_type", StringType(), True),
        StructField("identification_number", StringType(), True),
        StructField("status", StringType(), True),
        StructField("ts_updated", TimestampType(), True),
    ]
)


def _make_job():
    """Instantiate the job without triggering ``BaseCoreModelSparkJob.__init__``,
    since the methods under test do not depend on Airflow / parser state.
    """
    with patch.object(CoreBrokersSparkJob, "__init__", lambda self: None):
        return CoreBrokersSparkJob()


@pytest.fixture
def core_brokers_job():
    return _make_job()


class TestProcessCompanyDocument:
    """Tests for ``_process_company_document`` — the new latest-by-ts behaviour."""

    def _run(self, spark_session, job, company_document_rows, document_rows):
        cd_df = spark_session.createDataFrame(
            company_document_rows, schema=_COMPANY_DOCUMENT_SCHEMA
        )
        d_df = spark_session.createDataFrame(document_rows, schema=_DOCUMENT_SCHEMA)
        result = job._process_company_document(cd_df, d_df)
        return {row["doc_id_company"]: row.asDict() for row in result.collect()}

    def test_picks_latest_document_per_type_ignoring_status(
        self, spark_session, core_brokers_job
    ):
        """Among multiple revisions of the same type, picks the one with the
        largest ts_updated. The ARCHIVED revision wins over the older ACTIVE
        one because the new logic ignores ``document.status``.
        """
        # arrange
        cd_rows = [(1, 10), (1, 11)]
        d_rows = [
            (
                10,
                "CNPJ",
                "12.345.678/0001-90",
                "ACTIVE",
                datetime(2025, 1, 1, 0, 0, 0),
            ),
            (
                11,
                "CNPJ",
                "98.765.432/0001-10",
                "ARCHIVED",
                datetime(2026, 5, 1, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert — the ARCHIVED but newer revision wins
        assert out[1]["cnpj"] == "98765432000110"
        assert out[1]["creci"] is None
        assert out[1]["rfc"] is None

    def test_includes_only_active_revision_when_active_is_newest(
        self, spark_session, core_brokers_job
    ):
        """Sanity check: the ACTIVE revision still wins when it is the newest."""
        # arrange
        cd_rows = [(1, 10), (1, 11)]
        d_rows = [
            (
                10,
                "CNPJ",
                "11.111.111/0001-11",
                "ARCHIVED",
                datetime(2025, 1, 1, 0, 0, 0),
            ),
            (
                11,
                "CNPJ",
                "22.222.222/0001-22",
                "ACTIVE",
                datetime(2026, 5, 1, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert
        assert out[1]["cnpj"] == "22222222000122"

    def test_each_document_type_picked_independently(
        self, spark_session, core_brokers_job
    ):
        """One company can have CRECI + CNPJ + RFC, each taken from its own
        latest revision. Cross-type ts_updated does not affect the choice.
        """
        # arrange
        cd_rows = [(1, 100), (1, 101), (1, 102), (1, 103)]
        d_rows = [
            (
                100,
                "CRECI",
                "CRECI-SP 9999",
                "DELETED",
                datetime(2026, 4, 15, 0, 0, 0),
            ),
            (
                101,
                "CRECI",
                "CRECI-SP 0001",
                "ACTIVE",
                datetime(2024, 1, 1, 0, 0, 0),
            ),
            (
                102,
                "CNPJ",
                "12.345.678/0001-90",
                "ACTIVE",
                datetime(2026, 5, 5, 0, 0, 0),
            ),
            (
                103,
                "RFC",
                "ABCD-123-456-EFG",
                "ARCHIVED",
                datetime(2026, 5, 10, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert — each type independently picks its latest revision
        assert out[1]["creci"] == "CRECISP9999"
        assert out[1]["cnpj"] == "12345678000190"
        assert out[1]["rfc"] == "ABCD123456EFG"

    def test_multiple_companies_isolated(self, spark_session, core_brokers_job):
        """Companies do not leak documents to each other; each gets its own
        latest revision per type.
        """
        # arrange
        cd_rows = [(1, 200), (2, 201), (2, 202)]
        d_rows = [
            (
                200,
                "CNPJ",
                "11.111.111/0001-11",
                "ACTIVE",
                datetime(2026, 1, 1, 0, 0, 0),
            ),
            (
                201,
                "CNPJ",
                "33.333.333/0001-33",
                "ACTIVE",
                datetime(2024, 1, 1, 0, 0, 0),
            ),
            (
                202,
                "CNPJ",
                "44.444.444/0001-44",
                "DELETED",
                datetime(2026, 5, 1, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert
        assert out[1]["cnpj"] == "11111111000111"
        assert out[2]["cnpj"] == "44444444000144"  # newer revision (DELETED) wins

    def test_no_documents_for_a_type_yields_null(self, spark_session, core_brokers_job):
        """Company has CNPJ but no CRECI / RFC: those columns are NULL."""
        # arrange
        cd_rows = [(1, 300)]
        d_rows = [
            (
                300,
                "CNPJ",
                "12.345.678/0001-90",
                "ACTIVE",
                datetime(2026, 5, 1, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert
        assert out[1]["cnpj"] == "12345678000190"
        assert out[1]["creci"] is None
        assert out[1]["rfc"] is None

    def test_orphan_company_document_yields_all_nulls(
        self, spark_session, core_brokers_job
    ):
        """company_document points to an id_document that does not exist in
        document — the LEFT JOIN produces NULL columns and all three outputs
        come out NULL.
        """
        # arrange — id_document 999 has no match in the document fixture
        cd_rows = [(1, 999)]
        d_rows = [
            (
                500,
                "CNPJ",
                "12.345.678/0001-90",
                "ACTIVE",
                datetime(2026, 5, 1, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert — orphan reference produces a row with all NULL identifiers
        assert out[1]["creci"] is None
        assert out[1]["cnpj"] is None
        assert out[1]["rfc"] is None

    def test_identification_number_with_only_letters_yields_null_for_cnpj(
        self, spark_session, core_brokers_job
    ):
        """If the cleaned digits-only string is empty (CNPJ), output is NULL."""
        # arrange
        cd_rows = [(1, 600)]
        d_rows = [
            (
                600,
                "CNPJ",
                "no-digits-at-all",
                "ACTIVE",
                datetime(2026, 5, 1, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert — empty cleaned string maps to NULL by contract
        assert out[1]["cnpj"] is None

    def test_null_ts_updated_is_ignored_in_favor_of_dated_revision(
        self, spark_session, core_brokers_job
    ):
        """A revision with NULL ts_updated cannot be the "latest" — the
        dated revision wins, even if older-looking.
        """
        # arrange
        cd_rows = [(1, 700), (1, 701)]
        d_rows = [
            (
                700,
                "CNPJ",
                "11.111.111/0001-11",
                "ACTIVE",
                None,  # no timestamp
            ),
            (
                701,
                "CNPJ",
                "22.222.222/0001-22",
                "ACTIVE",
                datetime(2024, 1, 1, 0, 0, 0),
            ),
        ]

        # act
        out = self._run(spark_session, core_brokers_job, cd_rows, d_rows)

        # assert — the dated revision wins; NULL ts_updated is excluded
        assert out[1]["cnpj"] == "22222222000122"


_COMPANY_PRODUCT_SCHEMA = StructType(
    [
        StructField("id_company", LongType(), True),
        StructField("id_product", LongType(), True),
        StructField("status", StringType(), True),
    ]
)


class TestProcessCompanyProduct:
    """Tests for ``_process_company_product`` — product filter and 3P flag aggregation."""

    def _run(self, spark_session, job, rows):
        df = spark_session.createDataFrame(rows, schema=_COMPANY_PRODUCT_SCHEMA)
        result = job._process_company_product(df)
        return {row["id_company"]: row.asDict() for row in result.collect()}

    def test_product_40_company_appears_in_output(
        self, spark_session, core_brokers_job
    ):
        """A company with only product 40 (Alias) must be included after the filter."""
        rows = [(1, 40, "ACTIVE")]
        out = self._run(spark_session, core_brokers_job, rows)
        assert 1 in out

    def test_product_40_is_3p_flags_are_false(self, spark_session, core_brokers_job):
        """Alias-only companies must not get any 3P rent/sale/active flags."""
        rows = [(1, 40, "ACTIVE")]
        out = self._run(spark_session, core_brokers_job, rows)
        row = out[1]
        assert row["is_3p_rent_broker"] is False
        assert row["is_3p_sale_broker"] is False
        assert row["is_3p_active_broker"] is False
        assert row["is_3p_active_rent_broker"] is False
        assert row["is_3p_active_sale_broker"] is False

    def test_rede_and_alias_products_coexist(self, spark_session, core_brokers_job):
        """A company with both product 27 and product 40 retains its 3P sale flag."""
        rows = [(1, 27, "ACTIVE"), (1, 40, "ACTIVE")]
        out = self._run(spark_session, core_brokers_job, rows)
        row = out[1]
        assert row["is_3p_sale_broker"] is True
        assert row["is_3p_rent_broker"] is False

    def test_product_not_in_scope_excluded(self, spark_session, core_brokers_job):
        """Products other than 27, 30, 40 must be filtered out."""
        rows = [(1, 1, "ACTIVE"), (2, 40, "ACTIVE")]
        out = self._run(spark_session, core_brokers_job, rows)
        assert 1 not in out
        assert 2 in out


_COMPANY_SCHEMA = StructType(
    [
        StructField("id", LongType(), True),
        StructField("ts_updated", TimestampType(), True),
    ]
)

_COMPANY_VIEW = "test_company_for_load_data"


def _register_company_table(spark_session, rows):
    df = spark_session.createDataFrame(rows, schema=_COMPANY_SCHEMA)
    df.createOrReplaceTempView(_COMPANY_VIEW)
    return df


class TestLoadData:
    """Tests for ``CoreBrokersBaseSparkJob._load_data`` full vs incremental filtering."""

    def test_full_load_returns_all_rows_without_date_filter(
        self, spark_session, core_brokers_job
    ):
        # arrange
        _register_company_table(
            spark_session,
            [
                (1, datetime(2025, 1, 1, 0, 0, 0)),
                (2, datetime(2026, 6, 1, 0, 0, 0)),
            ],
        )
        args = SimpleNamespace(
            load_start_date="2026-01-01",
            load_end_date="2026-01-31",
        )

        # act — default full load does not apply date filter
        result = core_brokers_job._load_data(spark_session, _COMPANY_VIEW, args)

        # assert
        assert result.count() == 2

    def test_incremental_backfill_filters_when_apply_date_filter_and_dates_set(
        self, spark_session, core_brokers_job
    ):
        # arrange
        _register_company_table(
            spark_session,
            [
                (1, datetime(2025, 12, 15, 0, 0, 0)),
                (2, datetime(2026, 1, 15, 0, 0, 0)),
                (3, datetime(2026, 2, 1, 0, 0, 0)),
            ],
        )
        args = SimpleNamespace(
            load_start_date="2026-01-01",
            load_end_date="2026-01-31",
        )

        # act
        result = core_brokers_job._load_data(
            spark_session,
            _COMPANY_VIEW,
            args,
            apply_date_filter=True,
        )

        # assert — only company 2 falls in the January window
        ids = [row["id"] for row in result.collect()]
        assert ids == [2]

    def test_incremental_backfill_skips_filter_when_dates_empty(
        self, spark_session, core_brokers_job
    ):
        # arrange
        _register_company_table(
            spark_session,
            [
                (1, datetime(2025, 1, 1, 0, 0, 0)),
                (2, datetime(2026, 6, 1, 0, 0, 0)),
            ],
        )
        args = SimpleNamespace(
            load_start_date=None,
            load_end_date=None,
        )

        # act
        result = core_brokers_job._load_data(
            spark_session,
            _COMPANY_VIEW,
            args,
            apply_date_filter=True,
        )

        # assert
        assert result.count() == 2


class TestRunPipelineOverride:
    """Verifies that CoreBrokersSparkJob.run_pipeline delegates to _run_pipeline_with_config."""

    def test_run_pipeline_calls_run_pipeline_with_config(self, core_brokers_job):
        from unittest.mock import MagicMock, patch

        df = MagicMock()
        args = MagicMock()
        spark = MagicMock()

        with patch.object(
            core_brokers_job,
            "_run_pipeline_with_config",
        ) as mock_run:
            core_brokers_job.run_pipeline(df, args, spark)

        mock_run.assert_called_once_with(
            df,
            args,
            spark,
            merge_on_key="merge_on_brokers",
            update_condition_key="when_matched_update_condition_brokers",
        )
