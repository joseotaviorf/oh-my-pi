"""
Unit tests for broker name tag helpers in load_core_brokers.
"""

import pytest
from pyspark.sql.functions import col
from pyspark.sql.types import StringType, StructField, StructType

from dags.core.core_brokers.spark_jobs.load_core_brokers import _broker_string_tag


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
