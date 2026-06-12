"""Tests for load_security_data_gateway_findings_raw.py.

Section A   — mocked unit tests: verify merge contract and DeltaLoader call shape.
Section A.2 — parse/flatten unit tests: verify _parse_and_flatten + _filter_invalid_rows.
Section B   — local Spark+Delta integration tests: verify idempotency semantics.
Section C   — nested-JSON queryability test.
"""

import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch


# Allow `from dags.tech_platform...` imports
# Stubs for heavy dependencies are applied in conftest.py before this module is imported.
def _repo_root() -> str:
    cur = os.path.abspath(os.path.dirname(__file__))
    while cur != os.path.dirname(cur):
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
        cur = os.path.dirname(cur)
    raise RuntimeError("Cannot find repo root")


sys.path.insert(0, _repo_root())

from dags.tech_platform.security_data_gateway_findings.spark_jobs.load_security_data_gateway_findings_raw import (  # noqa: E402
    _OUTPUT_COLUMNS,
    DATABASE_NAME,
    MERGE_ON,
    TABLE_NAME,
    WHEN_MATCHED_UPDATE_CONDITION,
    LoadSecurityDataGatewayFindingsRawJob,
    _dedupe_batch,
    _filter_invalid_rows,
    _parse_and_flatten,
    build_merge_fn,
)

# ===========================================================================
# Section A — Mocked unit tests
# ===========================================================================


class TestParseArgs(unittest.TestCase):
    """parse_args must expose attributes BaseCoreModelSparkJob.run() reads."""

    @patch(
        "sys.argv",
        [
            "load_security_data_gateway_findings_raw",
            "forno",
            "quintoandar-datalake-forno",
            "security_data_gateway_findings",
            '["year", "month", "day"]',
            "2026-06-01",
        ],
    )
    def test_parse_args_exposes_base_run_attributes(self):
        args = LoadSecurityDataGatewayFindingsRawJob().parse_args()

        self.assertEqual(args.environment, "forno")
        self.assertEqual(args.bucket, "quintoandar-datalake-forno")
        self.assertEqual(args.schema, "security_data_gateway_findings")
        self.assertEqual(args.partitions, '["year", "month", "day"]')
        self.assertEqual(args.execution_date, "2026-06-01")
        self.assertEqual(args.dag_name, "security_data_gateway_findings")
        self.assertEqual(args.table_name, TABLE_NAME)

        # BaseCoreModelSparkJob.run() logging line must not raise AttributeError.
        log_line = (
            f"environment={args.environment}, "
            f"bucket={args.bucket}, table={args.table_name}"
        )
        self.assertIn("security_findings", log_line)

    @patch(
        "sys.argv",
        [
            "load_security_data_gateway_findings_raw",
            "forno",
            "quintoandar-datalake-forno",
            "security_data_gateway_findings",
            '["year", "month", "day"]',
            "2026-06-01",
            "--target-database-name",
            "cluster_validation",
            "--target-table-name",
            "datalake_security_data_gateway_raw___security_findings",
        ],
    )
    def test_parse_args_accepts_validation_flags(self):
        args = LoadSecurityDataGatewayFindingsRawJob().parse_args()

        self.assertEqual(args.target_database_name, "cluster_validation")
        self.assertEqual(
            args.target_table_name,
            "datalake_security_data_gateway_raw___security_findings",
        )


class TestMergeContract(unittest.TestCase):
    """Asserts the merge keys and update-condition strings match the spec."""

    def test_merge_on_keys(self):
        self.assertEqual(MERGE_ON, ["source", "resource_id"])

    def test_when_matched_update_condition(self):
        self.assertEqual(
            WHEN_MATCHED_UPDATE_CONDITION,
            "source.classified_at >= target.classified_at",
        )

    def test_build_merge_fn_calls_delta_loader_with_correct_merge_on(self):
        mock_spark = MagicMock()
        mock_delta_loader_cls = MagicMock()
        mock_delta_loader = MagicMock()
        mock_delta_loader_cls.return_value = mock_delta_loader

        mock_batch_df = MagicMock()

        with (
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw.DeltaLoader",
                mock_delta_loader_cls,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw._parse_and_flatten",
                return_value=mock_batch_df,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw._filter_invalid_rows",
                return_value=mock_batch_df,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw._dedupe_batch",
                return_value=mock_batch_df,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw.UnityCatalogHelper"
            ) as mock_uc,
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw.TablePrivileges"
            ),
        ):
            mock_uc.is_cluster_unity_catalog_enabled.return_value = False
            merge_fn = build_merge_fn(
                mock_spark,
                "s3://bucket/path",
                "datalake_security_data_gateway_raw.security_findings",
            )
            merge_fn(mock_batch_df, 0)

        mock_delta_loader.load_table.assert_called_once()
        call_kwargs = mock_delta_loader.load_table.call_args[1]
        self.assertEqual(call_kwargs["merge_on"], ["source", "resource_id"])
        self.assertEqual(
            call_kwargs["when_matched_update_condition"],
            "source.classified_at >= target.classified_at",
        )
        self.assertEqual(call_kwargs["partition_by"], ["year", "month", "day"])
        self.assertNotIn("when_matched_operation", call_kwargs)

    def test_build_merge_fn_calls_optimize_after_merge(self):
        mock_spark = MagicMock()
        mock_delta_loader_cls = MagicMock()
        mock_delta_loader = MagicMock()
        mock_delta_loader_cls.return_value = mock_delta_loader

        mock_batch_df = MagicMock()

        def _mock_filter(df, dq_counter):
            dq_counter["valid_rows"] = 1
            dq_counter["invalid_rows"] = 0
            return mock_batch_df

        with (
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw.DeltaLoader",
                mock_delta_loader_cls,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw._parse_and_flatten",
                return_value=mock_batch_df,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw._filter_invalid_rows",
                side_effect=_mock_filter,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw._dedupe_batch",
                return_value=mock_batch_df,
            ),
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw.UnityCatalogHelper"
            ) as mock_uc,
            patch(
                "dags.tech_platform.security_data_gateway_findings.spark_jobs"
                ".load_security_data_gateway_findings_raw.TablePrivileges"
            ),
        ):
            mock_uc.is_cluster_unity_catalog_enabled.return_value = False
            merge_fn = build_merge_fn(
                mock_spark,
                "s3://bucket/path",
                "datalake_security_data_gateway_raw.security_findings",
            )
            merge_fn(mock_batch_df, 0)

        mock_delta_loader.optimize_table.assert_called_once_with(
            "datalake_security_data_gateway_raw.security_findings",
            z_order_by=["resource_id"],
        )


class TestRunPipelineWriteTarget(unittest.TestCase):
    """run_pipeline must not treat the Airflow {schema} positional arg as UC database."""

    @patch(
        "dags.tech_platform.security_data_gateway_findings.spark_jobs"
        ".load_security_data_gateway_findings_raw.resolve_datalake_write_target",
        return_value=(
            DATABASE_NAME,
            TABLE_NAME,
            "s3://quintoandar-datalake-forno/raw/security_findings",
        ),
    )
    @patch(
        "dags.tech_platform.security_data_gateway_findings.spark_jobs"
        ".load_security_data_gateway_findings_raw.build_merge_fn",
        return_value=lambda *_args, **_kwargs: None,
    )
    def test_run_pipeline_uses_metadata_database_not_airflow_schema_arg(
        self, _mock_merge_fn, mock_resolve
    ):
        job = LoadSecurityDataGatewayFindingsRawJob()
        job.config_service = MagicMock()
        job.config_service.get_config.side_effect = lambda key: {
            "path_prefix": "s3://",
            "load_path_suffix": "/raw/security_findings/security_findings",
            "checkpoints_path_suffix": "/raw/security_findings/checkpoints",
        }[key]
        job.logger = MagicMock()

        args = MagicMock()
        args.bucket = "quintoandar-datalake-forno"
        args.schema = "security_data_gateway_findings"
        args.target_database_name = None
        args.target_table_name = None

        mock_stream = MagicMock()
        mock_query = MagicMock()
        mock_stream.writeStream.foreachBatch.return_value.trigger.return_value.option.return_value.start.return_value = mock_query

        job.run_pipeline(mock_stream, args, MagicMock())

        mock_resolve.assert_called_once()
        self.assertEqual(
            mock_resolve.call_args.kwargs["prod_database"],
            DATABASE_NAME,
        )
        self.assertNotEqual(
            mock_resolve.call_args.kwargs["prod_database"],
            args.schema,
        )


# ===========================================================================
# Section B — Local Spark+Delta integration tests
# These run with a real PySpark session and a temp directory for Delta.
# They are skipped automatically if Delta Lake is not available.
# ===========================================================================

try:
    from delta import configure_spark_with_delta_pip
    from pyspark.sql import SparkSession
    from pyspark.sql.functions import get_json_object
    from pyspark.sql.types import (
        IntegerType,
        LongType,
        StringType,
        StructField,
        StructType,
        TimestampType,
    )

    _DELTA_AVAILABLE = True
except ImportError:
    _DELTA_AVAILABLE = False


def _create_delta_spark_session(app_name: str, warehouse_dir: str) -> "SparkSession":
    # configure_spark_with_delta_pip wires the Delta JARs onto the local classpath;
    # plain SparkSession.builder alone does not, causing DeltaCatalog ClassNotFound.
    builder = (
        SparkSession.builder.master("local[1]")
        .appName(app_name)
        .config("spark.sql.warehouse.dir", warehouse_dir)
        .config("spark.sql.extensions", "io.delta.sql.DeltaSparkSessionExtension")
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .config("spark.databricks.delta.schema.autoMerge.enabled", "true")
        .config("spark.sql.shuffle.partitions", "1")
        .config("spark.driver.host", "127.0.0.1")
        .config("spark.sql.session.timeZone", "UTC")
    )
    spark = configure_spark_with_delta_pip(builder).getOrCreate()
    spark.sparkContext.setLogLevel("ERROR")
    return spark


def _make_finding(
    source: str = "drive_historical_backfill",
    resource_id: str = "file-1",
    classified_at: str = "2026-04-20T01:09:42Z",
    risk_level: str = "HIGH",
    mime_type: str = "application/pdf",
) -> str:
    return json.dumps(
        {
            "source": source,
            "event_type": "file_classified",
            "resource": {
                "resource_id": resource_id,
                "resource_type": "google_drive_file",
                "resource_name": "NDA.pdf",
                "location": "My Drive/Legal",
            },
            "actor": {"email": "carol@quintoandar.com"},
            "pii_types_detected": [
                {"pii_type": "CPF", "confidence_score": 0.97},
            ],
            "risk_level": risk_level,
            "source_metadata": json.dumps(
                {"mime_type": mime_type, "sharing_state": "PRIVATE"}
            ),
            "source_raw_payload": json.dumps({"fileId": resource_id}),
            "classified_at": classified_at,
        }
    )


# ===========================================================================
# Section A.2 — Parse/flatten unit tests
# Uses a plain SparkSession (no Delta JARs needed).
# ===========================================================================


@unittest.skipUnless(_DELTA_AVAILABLE, "pyspark not available in this environment")
class TestParseAndFlatten(unittest.TestCase):
    """Unit tests for _parse_and_flatten and _filter_invalid_rows."""

    @classmethod
    def setUpClass(cls):
        cls._warehouse = tempfile.mkdtemp(prefix="spark_wh_parse_")
        cls.spark = _create_delta_spark_session("test_parse_flatten", cls._warehouse)

    @classmethod
    def tearDownClass(cls):
        cls.spark.stop()
        shutil.rmtree(cls._warehouse, ignore_errors=True)

    def _make_raw_df(self, *finding_jsons: str):
        data = [(v,) for v in finding_jsons]
        return self.spark.createDataFrame(
            data, schema=StructType([StructField("value", StringType(), True)])
        )

    def _make_kafka_batch_df(self, *finding_jsons: str):
        """Mimic Spark Kafka readStream columns passed into foreachBatch."""
        data = [
            (
                b"key-bytes",
                finding_json,
                "forno_security-data-gateway.findings",
                0,
                idx,
                None,
                0,
            )
            for idx, finding_json in enumerate(finding_jsons)
        ]
        return self.spark.createDataFrame(
            data,
            schema=StructType(
                [
                    StructField("key", StringType(), True),
                    StructField("value", StringType(), True),
                    StructField("topic", StringType(), True),
                    StructField("partition", IntegerType(), True),
                    StructField("offset", LongType(), True),
                    StructField("timestamp", TimestampType(), True),
                    StructField("timestampType", IntegerType(), True),
                ]
            ),
        )

    def test_well_formed_finding_flattens_scalars_and_keeps_nested_as_json(self):
        raw = self._make_raw_df(_make_finding())
        result = _parse_and_flatten(raw)
        row = result.first()

        # Scalar top-level columns
        self.assertEqual(row["source"], "drive_historical_backfill")
        self.assertEqual(row["event_type"], "file_classified")
        self.assertEqual(row["resource_id"], "file-1")
        self.assertEqual(row["resource_type"], "google_drive_file")
        self.assertEqual(row["resource_name"], "NDA.pdf")
        self.assertEqual(row["location"], "My Drive/Legal")
        self.assertEqual(row["actor_email"], "carol@quintoandar.com")
        self.assertEqual(row["risk_level"], "HIGH")

        # Timestamp and partition columns
        self.assertIsNotNone(row["classified_at"])
        self.assertEqual(row["year"], 2026)
        self.assertEqual(row["month"], 4)
        self.assertEqual(row["day"], 20)
        self.assertIsNotNone(row["ts_load"])

        # pii_types_detected: typed array, not a JSON string
        self.assertIsNotNone(row["pii_types_detected"])
        self.assertEqual(len(row["pii_types_detected"]), 1)
        self.assertEqual(row["pii_types_detected"][0]["pii_type"], "CPF")
        self.assertAlmostEqual(
            row["pii_types_detected"][0]["confidence_score"], 0.97, places=2
        )

        # source_metadata / source_raw_payload: JSON strings, not None
        self.assertIsInstance(row["source_metadata"], str)
        self.assertIsInstance(row["source_raw_payload"], str)
        # Confirm they are valid JSON (no TypeError/ValueError)
        json.loads(row["source_metadata"])
        json.loads(row["source_raw_payload"])

    def test_kafka_stream_columns_are_not_in_output(self):
        raw = self._make_kafka_batch_df(_make_finding())
        parsed = _parse_and_flatten(raw)
        result = _dedupe_batch(parsed)

        self.assertEqual(result.columns, _OUTPUT_COLUMNS)
        self.assertNotIn("key", result.columns)
        self.assertNotIn("value", result.columns)
        self.assertNotIn("topic", result.columns)
        self.assertNotIn("offset", result.columns)
        self.assertNotIn("_kafka_offset", result.columns)
        self.assertNotIn("_kafka_partition", result.columns)

    def test_same_classified_at_in_batch_keeps_higher_kafka_offset(self):
        ts = "2026-04-20T01:09:42Z"
        low = _make_finding(classified_at=ts, risk_level="LOW")
        high = _make_finding(classified_at=ts, risk_level="HIGH")
        raw = self._make_kafka_batch_df(low, high)
        parsed = _parse_and_flatten(raw)
        valid = _filter_invalid_rows(parsed, {})
        deduped = _dedupe_batch(valid)

        self.assertEqual(deduped.count(), 1)
        self.assertEqual(deduped.first()["risk_level"], "HIGH")

    def test_same_classified_at_cross_partition_keeps_higher_kafka_offset(self):
        ts = "2026-04-20T01:09:42Z"
        low = _make_finding(classified_at=ts, risk_level="LOW")
        high = _make_finding(classified_at=ts, risk_level="HIGH")
        # "low" is on partition 0 with offset 10; "high" is on partition 1 with offset 20.
        # The old code ordered by partition ASC so partition 0 (LOW) would win.
        # The fix orders only by offset DESC so the higher offset (HIGH) wins.
        data = [
            (b"key", low, "topic", 0, 10, None, 0),
            (b"key", high, "topic", 1, 20, None, 0),
        ]
        raw = self.spark.createDataFrame(
            data,
            schema=StructType(
                [
                    StructField("key", StringType(), True),
                    StructField("value", StringType(), True),
                    StructField("topic", StringType(), True),
                    StructField("partition", IntegerType(), True),
                    StructField("offset", LongType(), True),
                    StructField("timestamp", TimestampType(), True),
                    StructField("timestampType", IntegerType(), True),
                ]
            ),
        )
        parsed = _parse_and_flatten(raw)
        valid = _filter_invalid_rows(parsed, {})
        deduped = _dedupe_batch(valid)

        self.assertEqual(deduped.count(), 1)
        self.assertEqual(deduped.first()["risk_level"], "HIGH")

    def test_same_classified_at_without_kafka_metadata_is_deterministic(self):
        ts = "2026-04-20T01:09:42Z"
        f1 = _make_finding(classified_at=ts, risk_level="LOW")
        f2 = _make_finding(classified_at=ts, risk_level="HIGH")
        raw = self._make_raw_df(f1, f2)
        parsed = _parse_and_flatten(raw)
        valid = _filter_invalid_rows(parsed, {})

        first_winner = _dedupe_batch(valid).first()["risk_level"]
        second_winner = _dedupe_batch(valid).first()["risk_level"]

        self.assertEqual(first_winner, second_winner)

    def test_optional_actor_absent_yields_null_actor_email_and_row_is_kept(self):
        finding = json.loads(_make_finding())
        del finding["actor"]
        raw = self._make_raw_df(json.dumps(finding))

        parsed = _parse_and_flatten(raw)
        dq: dict = {}
        valid = _filter_invalid_rows(parsed, dq)

        self.assertEqual(valid.count(), 1)
        self.assertIsNone(valid.first()["actor_email"])
        self.assertEqual(dq.get("invalid_rows", 0), 0)

    def test_optional_resource_fields_absent_yields_null_columns_and_row_is_kept(self):
        finding = json.loads(_make_finding())
        del finding["resource"]["resource_name"]
        del finding["resource"]["location"]
        raw = self._make_raw_df(json.dumps(finding))

        parsed = _parse_and_flatten(raw)
        dq: dict = {}
        valid = _filter_invalid_rows(parsed, dq)

        self.assertEqual(valid.count(), 1)
        row = valid.first()
        self.assertIsNone(row["resource_name"])
        self.assertIsNone(row["location"])
        self.assertEqual(dq.get("invalid_rows", 0), 0)

    def test_malformed_message_missing_required_field_is_filtered(self):
        finding = json.loads(_make_finding())
        del finding["risk_level"]
        raw = self._make_raw_df(json.dumps(finding))

        parsed = _parse_and_flatten(raw)
        dq: dict = {}
        valid = _filter_invalid_rows(parsed, dq)

        self.assertEqual(valid.count(), 0)
        self.assertEqual(dq["invalid_rows"], 1)


@unittest.skipUnless(_DELTA_AVAILABLE, "delta-spark not available in this environment")
class TestFindingsIntegration(unittest.TestCase):
    """Local Spark+Delta integration tests — no live Kafka or cluster needed."""

    @classmethod
    def setUpClass(cls):
        cls._warehouse = tempfile.mkdtemp(prefix="spark_wh_findings_")
        cls.spark = _create_delta_spark_session(
            "test_security_findings", cls._warehouse
        )

    @classmethod
    def tearDownClass(cls):
        cls.spark.stop()
        shutil.rmtree(cls._warehouse, ignore_errors=True)

    def setUp(self):
        # Each test gets a clean catalog slate so different tmpdirs don't confuse
        # DeltaLoader.forName, which resolves the merge target by catalog name.
        self.spark.sql("DROP TABLE IF EXISTS default.security_findings_test")

    def _make_raw_df(self, *finding_jsons: str):
        """Wrap raw JSON strings in a 'value' column (mimics Kafka readStream output)."""
        data = [(v,) for v in finding_jsons]
        return self.spark.createDataFrame(
            data, schema=StructType([StructField("value", StringType(), True)])
        )

    def _run_merge(self, raw_df, table_path: str):
        """Parse, filter, dedupe, then DeltaLoader merge into a temp Delta table."""
        # The module-level stub setup uses setdefault, so the real package is never
        # loaded automatically. Pop the stub here to force a real import.
        sys.modules.pop("bietlejuice.loaders.delta_loader", None)
        from bietlejuice.loaders.delta_loader import DeltaLoader

        flattened = _parse_and_flatten(raw_df)
        dq: dict = {}
        valid = _filter_invalid_rows(flattened, dq)
        deduped = _dedupe_batch(valid)

        loader = DeltaLoader(self.spark)
        loader.load_table(
            table_name="default.security_findings_test",
            path=table_path,
            source_df=deduped,
            partition_by=["year", "month", "day"],
            merge_on=["source", "resource_id"],
            when_matched_update_condition="source.classified_at >= target.classified_at",
        )
        return dq

    def test_duplicate_delivery_yields_one_row(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            finding = _make_finding()
            self._run_merge(self._make_raw_df(finding), tmpdir)
            self._run_merge(self._make_raw_df(finding), tmpdir)

            result = self.spark.read.format("delta").load(tmpdir)
            self.assertEqual(result.count(), 1)

    def test_newer_classified_at_updates_row(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            old = _make_finding(classified_at="2026-04-20T01:00:00Z", risk_level="LOW")
            self._run_merge(self._make_raw_df(old), tmpdir)

            newer = _make_finding(
                classified_at="2026-04-20T02:00:00Z", risk_level="HIGH"
            )
            self._run_merge(self._make_raw_df(newer), tmpdir)

            result = self.spark.read.format("delta").load(tmpdir)
            self.assertEqual(result.count(), 1)
            self.assertEqual(result.first()["risk_level"], "HIGH")

    def test_newer_full_snapshot_with_null_actor_clears_actor_email(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            self._run_merge(self._make_raw_df(_make_finding()), tmpdir)

            finding = json.loads(
                _make_finding(
                    classified_at="2026-04-20T02:00:00Z",
                    risk_level="CRITICAL",
                )
            )
            finding["actor"] = {"email": None}
            self._run_merge(self._make_raw_df(json.dumps(finding)), tmpdir)

            row = self.spark.read.format("delta").load(tmpdir).first()
            self.assertEqual(row["risk_level"], "CRITICAL")
            self.assertIsNone(row["actor_email"])

    def test_older_classified_at_does_not_overwrite(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            newer = _make_finding(
                classified_at="2026-04-20T02:00:00Z", risk_level="HIGH"
            )
            self._run_merge(self._make_raw_df(newer), tmpdir)

            older = _make_finding(
                classified_at="2026-04-20T01:00:00Z", risk_level="LOW"
            )
            self._run_merge(self._make_raw_df(older), tmpdir)

            result = self.spark.read.format("delta").load(tmpdir)
            self.assertEqual(result.count(), 1)
            self.assertEqual(result.first()["risk_level"], "HIGH")

    def test_same_key_twice_in_batch_deduped_to_one_row(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            f1 = _make_finding(classified_at="2026-04-20T01:00:00Z", risk_level="LOW")
            f2 = _make_finding(classified_at="2026-04-20T02:00:00Z", risk_level="HIGH")
            raw = self._make_raw_df(f1, f2)
            self._run_merge(raw, tmpdir)

            result = self.spark.read.format("delta").load(tmpdir)
            self.assertEqual(result.count(), 1)
            self.assertEqual(result.first()["risk_level"], "HIGH")

    def test_same_classified_at_in_batch_merges_to_latest_kafka_offset(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            ts = "2026-04-20T01:09:42Z"
            older = _make_finding(classified_at=ts, risk_level="LOW")
            newer = _make_finding(classified_at=ts, risk_level="HIGH")
            data = [
                (
                    b"key-bytes",
                    older,
                    "forno_security-data-gateway.findings",
                    0,
                    10,
                    None,
                    0,
                ),
                (
                    b"key-bytes",
                    newer,
                    "forno_security-data-gateway.findings",
                    0,
                    20,
                    None,
                    0,
                ),
            ]
            raw = self.spark.createDataFrame(
                data,
                schema=StructType(
                    [
                        StructField("key", StringType(), True),
                        StructField("value", StringType(), True),
                        StructField("topic", StringType(), True),
                        StructField("partition", IntegerType(), True),
                        StructField("offset", LongType(), True),
                        StructField("timestamp", TimestampType(), True),
                        StructField("timestampType", IntegerType(), True),
                    ]
                ),
            )
            self._run_merge(raw, tmpdir)

            result = self.spark.read.format("delta").load(tmpdir)
            self.assertEqual(result.count(), 1)
            self.assertEqual(result.first()["risk_level"], "HIGH")


# ===========================================================================
# Section C — Nested-JSON queryability test
# ===========================================================================


@unittest.skipUnless(_DELTA_AVAILABLE, "delta-spark not available in this environment")
class TestNestedJsonQueryability(unittest.TestCase):
    """Asserts that source_metadata sub-fields are extractable after writing."""

    @classmethod
    def setUpClass(cls):
        cls._warehouse = tempfile.mkdtemp(prefix="spark_wh_json_")
        cls.spark = _create_delta_spark_session("test_nested_json", cls._warehouse)

    @classmethod
    def tearDownClass(cls):
        cls.spark.stop()
        shutil.rmtree(cls._warehouse, ignore_errors=True)

    def test_source_metadata_mime_type_extractable(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            sys.modules.pop("bietlejuice.loaders.delta_loader", None)
            from bietlejuice.loaders.delta_loader import DeltaLoader

            finding = _make_finding(mime_type="application/pdf")
            raw = self.spark.createDataFrame(
                [(finding,)],
                schema=StructType([StructField("value", StringType(), True)]),
            )
            flattened = _parse_and_flatten(raw)
            dq: dict = {}
            valid = _filter_invalid_rows(flattened, dq)
            deduped = _dedupe_batch(valid)

            DeltaLoader(self.spark).load_table(
                table_name="default.findings_json_test",
                path=tmpdir,
                source_df=deduped,
                partition_by=["year", "month", "day"],
                merge_on=["source", "resource_id"],
                when_matched_update_condition="source.classified_at >= target.classified_at",
            )

            result = (
                self.spark.read.format("delta")
                .load(tmpdir)
                .withColumn(
                    "mime_type", get_json_object("source_metadata", "$.mime_type")
                )
                .first()
            )
            self.assertEqual(result["mime_type"], "application/pdf")


if __name__ == "__main__":
    unittest.main()
