"""
Unit tests for privacy functions (k-anonymity).
"""

from pyspark.sql import functions as F


class TestApplyKAnonymity:
    """Integration tests for apply_k_anonymity function."""

    def test_apply_k_anonymity_redacts_dimensions(self, spark):
        """Test that dimension columns are redacted when count < k."""
        from bietlejuice.qube.jobs.common.privacy import apply_k_anonymity

        data = [
            ("2025-06-29", "RENT", "Scheduled", 1),
            ("2025-06-29", "SALE", "Done", 15),
        ]
        df = spark.createDataFrame(data, ["date", "dim_context", "dim_status", "count"])

        dim_cols = [("dim_context", "string"), ("dim_status", "string")]
        measure_cols = ["count"]

        result = apply_k_anonymity(df, dim_cols, measure_cols, k=10)
        rows = result.collect()

        results_map = {r["count"]: r for r in rows}

        assert results_map[1]["dim_context"] == "___REDACTED___"
        assert results_map[1]["dim_status"] == "___REDACTED___"
        assert results_map[15]["dim_context"] == "SALE"
        assert results_map[15]["dim_status"] == "Done"

    def test_apply_k_anonymity_preserves_counts(self, spark):
        """Test that count values are preserved."""
        from bietlejuice.qube.jobs.common.privacy import apply_k_anonymity

        data = [
            ("2025-06-29", "RENT", 5),
        ]
        df = spark.createDataFrame(data, ["date", "dim_context", "count"])

        dim_cols = [("dim_context", "string")]
        measure_cols = ["count"]

        result = apply_k_anonymity(df, dim_cols, measure_cols, k=10)
        rows = result.collect()

        assert rows[0]["count"] == 5

    def test_apply_k_anonymity_zero_count_not_redacted(self, spark):
        """Test zero counts are not redacted."""
        from bietlejuice.qube.jobs.common.privacy import apply_k_anonymity

        data = [
            ("2025-06-29", "RENT", 0),
            ("2025-06-29", "SALE", 5),
        ]
        df = spark.createDataFrame(data, ["date", "dim_context", "count"])

        dim_cols = [("dim_context", "string")]
        measure_cols = ["count"]

        result = apply_k_anonymity(df, dim_cols, measure_cols, k=10)
        rows = result.collect()

        results_map = {r["count"]: r for r in rows}

        # Zero count should NOT be redacted (nothing to hide)
        assert results_map[0]["dim_context"] == "RENT"
        # count=5 should be redacted (0 < 5 < 10)
        assert results_map[5]["dim_context"] == "___REDACTED___"

    def test_apply_k_anonymity_at_threshold(self, spark):
        """Test count exactly at k threshold is not redacted."""
        from bietlejuice.qube.jobs.common.privacy import apply_k_anonymity

        data = [
            ("2025-06-29", "RENT", 10),
            ("2025-06-29", "SALE", 9),
        ]
        df = spark.createDataFrame(data, ["date", "dim_context", "count"])

        dim_cols = [("dim_context", "string")]
        measure_cols = ["count"]

        result = apply_k_anonymity(df, dim_cols, measure_cols, k=10)
        rows = result.collect()

        results_map = {r["count"]: r for r in rows}

        # count=10 is exactly k, should NOT be redacted
        assert results_map[10]["dim_context"] == "RENT"
        # count=9 is < k, should be redacted
        assert results_map[9]["dim_context"] == "___REDACTED___"

    def test_apply_k_anonymity_k_equals_1(self, spark):
        """Test k=1 means no redaction for any count >= 1."""
        from bietlejuice.qube.jobs.common.privacy import apply_k_anonymity

        data = [
            ("2025-06-29", "RENT", 1),
            ("2025-06-29", "SALE", 2),
        ]
        df = spark.createDataFrame(data, ["date", "dim_context", "count"])

        dim_cols = [("dim_context", "string")]
        measure_cols = ["count"]

        result = apply_k_anonymity(df, dim_cols, measure_cols, k=1)
        rows = result.collect()

        # With k=1, condition is (count > 0 AND count < 1) which is always False
        # So nothing should be redacted
        for r in rows:
            assert r["dim_context"] in ["RENT", "SALE"]

    def test_apply_k_anonymity_multiple_measures(self, spark):
        """Test k-anonymity with multiple measure columns."""
        from bietlejuice.qube.jobs.common.privacy import apply_k_anonymity

        # If ANY measure count is < k, dimensions should be redacted
        data = [
            ("2025-06-29", "RENT", 15, 5),  # count1 safe, count2 unsafe -> redact
            ("2025-06-29", "SALE", 5, 15),  # count1 unsafe, count2 safe -> redact
            ("2025-06-29", "BOTH", 15, 15),  # both safe -> no redact
        ]
        df = spark.createDataFrame(data, ["date", "dim_context", "count1", "count2"])

        dim_cols = [("dim_context", "string")]
        measure_cols = ["count1", "count2"]

        result = apply_k_anonymity(df, dim_cols, measure_cols, k=10)
        rows = result.collect()

        results_map = {(r["count1"], r["count2"]): r for r in rows}

        # (15, 5) -> count2=5 < k -> redact
        assert results_map[(15, 5)]["dim_context"] == "___REDACTED___"
        # (5, 15) -> count1=5 < k -> redact
        assert results_map[(5, 15)]["dim_context"] == "___REDACTED___"
        # (15, 15) -> both safe -> no redact
        assert results_map[(15, 15)]["dim_context"] == "BOTH"


class TestRedactValue:
    """Tests for redact_value function."""

    def test_redact_string(self, spark):
        """Test string redaction."""
        from bietlejuice.qube.jobs.common.privacy import redact_value

        df = spark.createDataFrame([("test",)], ["val"])
        result = df.select(redact_value(F.col("val"), "string").alias("redacted"))

        row = result.collect()[0]
        assert row["redacted"] == "___REDACTED___"

    def test_redact_number(self, spark):
        """Test number redaction returns sentinel value."""
        from bietlejuice.qube.jobs.common.privacy import redact_value

        df = spark.createDataFrame([(123.45,)], ["val"])
        result = df.select(redact_value(F.col("val"), "number").alias("redacted"))

        row = result.collect()[0]
        # Number redaction returns -2147483648 (sentinel)
        assert row["redacted"] == -2147483648

    def test_redact_boolean(self, spark):
        """Test boolean redaction."""
        from bietlejuice.qube.jobs.common.privacy import redact_value

        df = spark.createDataFrame([(True,)], ["val"])
        result = df.select(redact_value(F.col("val"), "boolean").alias("redacted"))

        row = result.collect()[0]
        # Boolean redaction returns null
        assert row["redacted"] is None

    def test_redact_unknown_type(self, spark):
        """Test unknown type redaction returns null."""
        from bietlejuice.qube.jobs.common.privacy import redact_value

        df = spark.createDataFrame([("test",)], ["val"])
        result = df.select(redact_value(F.col("val"), "unknown").alias("redacted"))

        row = result.collect()[0]
        assert row["redacted"] is None
