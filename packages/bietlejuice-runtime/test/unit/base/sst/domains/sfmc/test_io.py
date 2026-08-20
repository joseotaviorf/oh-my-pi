from unittest import mock

import pytest
from pyspark.sql.utils import AnalysisException

from bietlejuice.base.sst.domains.sfmc.raw import io as io_module
from bietlejuice.base.sst.domains.sfmc.raw.io import (
    build_csv_path,
    read_csv,
    read_csv_if_exists,
    to_spark_path,
)

SENT_CSV = b"SubscriberKey,JobID\nsub-1,42\nsub-2,43\n"


class TestToSparkPath:
    @pytest.mark.parametrize(
        "given, expected",
        [
            ("s3://bucket/key.csv", "s3a://bucket/key.csv"),
            ("s3a://bucket/key.csv", "s3a://bucket/key.csv"),
            ("/local/tmp/key.csv", "/local/tmp/key.csv"),
        ],
    )
    def test_translates_only_the_s3_scheme(self, given, expected):
        assert to_spark_path(given) == expected


class TestBuildCsvPath:
    def test_builds_the_fixed_sfmc_key(self):
        path = build_csv_path(
            "s3a://5a-datalake-prod/raw/sfmc/tracking-data",
            "send",
            "growth",
            "2026-08-05",
        )

        assert path == (
            "s3a://5a-datalake-prod/raw/sfmc/tracking-data/send_growth_2026-08-05.csv"
        )

    def test_strips_a_trailing_slash_from_the_prefix(self):
        path = build_csv_path(
            "s3a://5a-datalake-prod/raw/sfmc/tracking-data/",
            "return",
            "growth",
            "2026-08-05",
        )

        assert path == (
            "s3a://5a-datalake-prod/raw/sfmc/tracking-data/return_growth_2026-08-05.csv"
        )


class TestReadCsv:
    def test_reads_header_and_infers_types(self, spark_session, tmp_path):
        csv_file = tmp_path / "send_growth_2026-08-05.csv"
        csv_file.write_bytes(SENT_CSV)

        df = read_csv(spark_session, str(csv_file))

        assert df.columns == ["SubscriberKey", "JobID"]
        assert dict(df.dtypes)["JobID"] == "int"
        assert dict(df.dtypes)["SubscriberKey"] == "string"
        assert df.count() == 2

    def test_reads_a_custom_delimiter(self, spark_session, tmp_path):
        csv_file = tmp_path / "send_growth_2026-08-05.csv"
        csv_file.write_bytes(b"SubscriberKey\tJobID\nsub-1\t42\n")

        df = read_csv(spark_session, str(csv_file), delimiter="\t")

        assert df.columns == ["SubscriberKey", "JobID"]
        assert df.collect()[0]["JobID"] == 42

    def test_keeps_quoted_newlines_inside_a_single_row(self, spark_session, tmp_path):
        csv_file = tmp_path / "send_growth_2026-08-05.csv"
        csv_file.write_bytes(b'SubscriberKey,Notes\nsub-1,"line one\nline two"\n')

        df = read_csv(spark_session, str(csv_file))

        assert df.count() == 1
        assert df.collect()[0]["Notes"] == "line one\nline two"

    def test_raises_when_the_path_does_not_exist(self, spark_session, tmp_path):
        with pytest.raises(AnalysisException):
            read_csv(spark_session, str(tmp_path / "missing.csv"))


class TestReadCsvIfExists:
    def test_reads_the_file_when_it_was_delivered(self, spark_session, tmp_path):
        csv_file = tmp_path / "send_growth_2026-08-05.csv"
        csv_file.write_bytes(SENT_CSV)

        df = read_csv_if_exists(spark_session, str(csv_file))

        assert df is not None
        assert df.count() == 2

    def test_returns_none_when_the_file_was_not_delivered(
        self, spark_session, tmp_path
    ):
        df = read_csv_if_exists(spark_session, str(tmp_path / "missing.csv"))

        assert df is None

    def test_propagates_an_analysis_exception_unrelated_to_a_missing_path(self):
        # A real file that Spark still rejects (e.g. malformed schema) must
        # fail loudly, not be swallowed as "not delivered yet".
        with mock.patch.object(
            io_module,
            "read_csv",
            side_effect=AnalysisException("[SOME_OTHER_ERROR] unrelated failure"),
        ):
            with pytest.raises(AnalysisException, match="unrelated failure"):
                read_csv_if_exists(mock.MagicMock(), "s3a://bucket/send_growth.csv")
