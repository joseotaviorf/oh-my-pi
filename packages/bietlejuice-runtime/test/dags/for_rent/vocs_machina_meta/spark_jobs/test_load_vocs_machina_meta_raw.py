"""Unit tests for load_vocs_machina_meta_raw.py's 4 build_*_df parse paths.

Fixture JSON is written to a local temp dir per test and read back through
each build function with a real (local) SparkSession, covering:
  - a run with a summary but NO throughput observation and NO backfill plan
    file (the common no-throughput/no-backfill-plan case), asserting the
    missing-glob-match case returns None instead of raising;
  - output columns for all 4 shapes, including the ts_load-derived
    year/month/day and s3_key columns added on every path;
  - effective_applicability staying a JSON string column (not a struct) in
    prompt_catalog_snapshots;
  - run_id extraction from the filename for backfill_plans (no run_id field
    in the JSON body itself).
"""

import json

import pytest

pytest.importorskip("pyspark")

from dags.for_rent.vocs_machina_meta.spark_jobs import (  # noqa: E402
    load_vocs_machina_meta_raw as job,
)

RUN_ID = "run-2026-08-23T00-00-00"


def _write_json(path, payload):
    # Pretty-printed (indent=2), matching the real multi-line `_meta/`
    # artifacts on S3 -- a bare json.dumps() (single physical line) does not
    # exercise the multiLine read path and previously masked VOCS-61.
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2))


def _write_jsonl(path, payloads):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(json.dumps(payload) for payload in payloads))


def _run_summary_payload(run_id=RUN_ID):
    return {
        "run_id": run_id,
        "window": {"start": "2026-08-22", "end": "2026-08-23"},
        "environment": "prod",
        "mode": "forward",
        "execution_backend": "async",
        "model": "gpt-test",
        "failed_sources": ["source_a"],
        "forward_tasks": 10,
        "backfill_tasks": 0,
        "prompts_backfilling": [],
        "metrics": {
            "planned_calls": 10,
            "completed_calls": 9,
            "failed_calls": 1,
            "calls_per_second": 1.5,
            "duration_seconds": 6.0,
            "classification_duration_seconds": 5.0,
            "retry_total": 2,
            "retry_429_total": 1,
            "prompt_tokens": 100,
            "completion_tokens": 50,
            "cached_tokens": 10,
            "cache_hit_rate": 0.1,
            "partitions_complete": 5,
            "partitions_incomplete": 0,
            "backfill_deferred_partitions": 0,
            "checkpoint_rows_written": 9,
            "source_fetch_failures": 0,
            "response_cost_usd": 0.05,
        },
        "throughput_calibration": {
            "calls_per_second": 1.5,
            "basis": "measured",
            "config_default": 1.0,
        },
        # No backfill_breaker / backfill_escalation_attribution -- both are
        # optional and this run didn't trigger either.
    }


def _backfill_plan_payload(**overrides):
    payload = {
        "partitions": 4,
        "estimated_calls": 200,
        "estimated_llm_seconds": 120.5,
        "estimated_wall_clock_seconds": 300,
        "estimated_runs_needed": 2,
        "estimate_basis_counts": {
            "measured_from_last_success": 3,
            "config_default": 1,
        },
        "caution": "high_volume",
        "throughput_calibration": {
            "calls_per_second": 1.5,
            "basis": "measured",
            "config_default": 1.0,
        },
        "backfill_breaker": {
            "tripped": False,
            "fingerprint": "xyz",
            "reasons": [],
            "n_prompts": 0,
            "n_partitions": 0,
            "estimated_calls": 0,
            "approved": None,
            "refused": False,
            "approved_pairs": [],
        },
    }
    payload.update(overrides)
    return payload


@pytest.fixture
def source_root(tmp_path):
    return tmp_path / "vocs-machina"


class TestBuildRunSummariesDf:
    def test_parses_expected_columns_and_optional_structs(self, spark, source_root):
        _write_json(
            source_root / "_meta" / "runs" / RUN_ID / "summary.json",
            _run_summary_payload(),
        )

        df = job.build_run_summaries_df(spark, str(source_root))

        assert df is not None
        row = df.collect()[0]
        assert row["run_id"] == RUN_ID
        assert row["window"]["start"] == "2026-08-22"
        assert row["metrics"]["completed_calls"] == 9
        assert row["metrics"]["response_cost_usd"] == pytest.approx(0.05)
        assert row["throughput_calibration"]["basis"] == "measured"
        # Optional structs absent from the fixture come back as null, not a
        # missing column or a raised error.
        assert row["backfill_breaker"] is None
        assert row["backfill_escalation_attribution"] is None
        for col in ("s3_key", "ts_load", "year", "month", "day"):
            assert col in df.columns
        assert row["s3_key"].endswith("summary.json")

    def test_backfill_breaker_struct_parses_when_present(self, spark, source_root):
        payload = _run_summary_payload()
        payload["backfill_breaker"] = {
            "tripped": True,
            "fingerprint": "abc123",
            "reasons": ["too_many_calls"],
            "n_prompts": 3,
            "n_partitions": 12,
            "estimated_calls": 500,
            "approved": None,
            "refused": False,
            "approved_pairs": [{"prompt_id": "p1", "prompt_hash": "h1"}],
        }
        _write_json(source_root / "_meta" / "runs" / RUN_ID / "summary.json", payload)

        df = job.build_run_summaries_df(spark, str(source_root))

        row = df.collect()[0]
        assert row["backfill_breaker"]["tripped"] is True
        assert row["backfill_breaker"]["approved"] is None
        assert row["backfill_breaker"]["approved_pairs"][0]["prompt_id"] == "p1"

    def test_duplicate_run_id_in_one_file_is_collapsed(self, spark, source_root):
        _write_jsonl(
            source_root / "_meta" / "runs" / RUN_ID / "summary.json",
            [_run_summary_payload(), _run_summary_payload()],
        )

        df = job.build_run_summaries_df(spark, str(source_root))

        assert df is not None
        assert df.count() == 1
        assert df.collect()[0]["run_id"] == RUN_ID


class TestBuildThroughputObservationsDf:
    def test_returns_none_when_no_files_match(self, spark, source_root):
        # Directory doesn't even exist -- this is the common case (at most
        # one throughput file per run, often zero).
        df = job.build_throughput_observations_df(spark, str(source_root))
        assert df is None

    def test_parses_expected_columns_when_present(self, spark, source_root):
        _write_json(
            source_root / "_meta" / "throughput" / f"{RUN_ID}.json",
            {
                "run_id": RUN_ID,
                "observed_at": "2026-08-23T00:05:00",
                "model": "gpt-test",
                "mode": "forward",
                "completed_calls": 9,
                "duration_seconds": 6.0,
                "calls_per_second": 1.5,
            },
        )

        df = job.build_throughput_observations_df(spark, str(source_root))

        assert df is not None
        row = df.collect()[0]
        assert row["run_id"] == RUN_ID
        assert row["calls_per_second"] == pytest.approx(1.5)
        for col in ("s3_key", "ts_load", "year", "month", "day"):
            assert col in df.columns
        assert row["s3_key"]
        assert row["s3_key"].endswith(f"{RUN_ID}.json")

    def test_multiple_samples_per_run_are_all_kept(self, spark, source_root):
        # A run emits many throughput files (one per sample, named
        # <observed_at>-<run_id>.json), so run_id alone is not the grain -- the
        # MERGE keys on [run_id, observed_at]. Distinct samples must all survive.
        base = {
            "run_id": RUN_ID,
            "model": "gpt-test",
            "mode": "forward",
            "completed_calls": 5,
            "duration_seconds": 3.0,
            "calls_per_second": 1.5,
        }
        _write_json(
            source_root / "_meta" / "throughput" / f"2026-08-23T00-05-00-{RUN_ID}.json",
            {**base, "observed_at": "2026-08-23T00:05:00"},
        )
        _write_json(
            source_root / "_meta" / "throughput" / f"2026-08-23T00-10-00-{RUN_ID}.json",
            {**base, "observed_at": "2026-08-23T00:10:00", "completed_calls": 9},
        )

        df = job.build_throughput_observations_df(spark, str(source_root))

        assert df is not None
        rows = df.collect()
        observed = {row["observed_at"] for row in rows}
        assert observed == {"2026-08-23T00:05:00", "2026-08-23T00:10:00"}
        keys = {row["s3_key"] for row in rows}
        assert all(key for key in keys)
        assert any(key.endswith(f"2026-08-23T00-05-00-{RUN_ID}.json") for key in keys)
        assert any(key.endswith(f"2026-08-23T00-10-00-{RUN_ID}.json") for key in keys)

    def test_exact_duplicate_sample_is_collapsed(self, spark, source_root):
        # Two files that carry an identical (run_id, observed_at) must not both
        # reach the MERGE (they would match one target key and abort it).
        sample = {
            "run_id": RUN_ID,
            "observed_at": "2026-08-23T00:05:00",
            "model": "gpt-test",
            "mode": "forward",
            "completed_calls": 5,
            "duration_seconds": 3.0,
            "calls_per_second": 1.5,
        }
        _write_json(source_root / "_meta" / "throughput" / f"a-{RUN_ID}.json", sample)
        _write_json(source_root / "_meta" / "throughput" / f"b-{RUN_ID}.json", sample)

        df = job.build_throughput_observations_df(spark, str(source_root))

        assert df is not None
        assert df.count() == 1
        s3_key = df.collect()[0]["s3_key"]
        assert s3_key
        assert s3_key.endswith(f"a-{RUN_ID}.json") or s3_key.endswith(
            f"b-{RUN_ID}.json"
        )


class TestBuildBackfillPlansDf:
    def test_returns_none_when_no_files_match(self, spark, source_root):
        df = job.build_backfill_plans_df(spark, str(source_root))
        assert df is None

    def test_run_id_extracted_from_filename_not_body(self, spark, source_root):
        # The JSON body itself carries no run_id field -- only the filename
        # does (_meta/backfill_plans/<run_id>.json).
        _write_json(
            source_root / "_meta" / "backfill_plans" / f"{RUN_ID}.json",
            _backfill_plan_payload(),
        )

        df = job.build_backfill_plans_df(spark, str(source_root))

        assert df is not None
        row = df.collect()[0]
        assert row["run_id"] == RUN_ID
        assert row["estimate_basis_counts"]["measured_from_last_success"] == 3
        for col in ("s3_key", "ts_load", "year", "month", "day"):
            assert col in df.columns

    def test_duplicate_run_id_in_one_file_is_collapsed(self, spark, source_root):
        payload = _backfill_plan_payload()
        _write_jsonl(
            source_root / "_meta" / "backfill_plans" / f"{RUN_ID}.json",
            [payload, payload],
        )

        df = job.build_backfill_plans_df(spark, str(source_root))

        assert df is not None
        assert df.count() == 1
        assert df.collect()[0]["run_id"] == RUN_ID

    def test_empty_run_id_rows_are_dropped(self, spark, source_root):
        _write_json(
            source_root / "_meta" / "backfill_plans" / ".json",
            _backfill_plan_payload(
                partitions=1,
                estimated_calls=1,
                estimated_llm_seconds=1.0,
                estimated_wall_clock_seconds=1,
                estimated_runs_needed=1,
                estimate_basis_counts={
                    "measured_from_last_success": 0,
                    "config_default": 1,
                },
                caution=None,
                throughput_calibration={
                    "calls_per_second": 1.0,
                    "basis": "config_default",
                    "config_default": 1.0,
                },
                backfill_breaker=None,
            ),
        )

        df = job.build_backfill_plans_df(spark, str(source_root))

        assert df is not None
        assert df.count() == 0


class TestBuildPromptCatalogSnapshotsDf:
    def test_explodes_one_row_per_prompt_and_keeps_applicability_as_json_string(
        self, spark, source_root
    ):
        effective_applicability = {"any_of": [{"field": "status", "eq": "active"}]}
        _write_json(
            source_root / "_meta" / "latest_active_prompts.json",
            {
                "generated_at": "2026-08-23T00:00:00",
                "run_id": RUN_ID,
                "prompts": [
                    {
                        "prompt_id": "p1",
                        "prompt_hash": "h1",
                        "classifier_contract_fingerprint": "fp1",
                        "effective_applicability": effective_applicability,
                        "active": True,
                        "collection": "nps",
                        "opportunity": "churn",
                        "backfill_days": 7,
                    },
                    {
                        "prompt_id": "p2",
                        "prompt_hash": "h2",
                        "classifier_contract_fingerprint": "fp2",
                        "effective_applicability": {"different": "shape"},
                        "active": False,
                        "collection": "nps",
                        "opportunity": "renewal",
                        "backfill_days": 0,
                    },
                ],
            },
        )

        df = job.build_prompt_catalog_snapshots_df(spark, str(source_root))

        assert df is not None
        rows = {row["prompt_id"]: row for row in df.collect()}
        assert set(rows) == {"p1", "p2"}
        assert rows["p1"]["run_id"] == RUN_ID
        assert rows["p1"]["generated_at"] == "2026-08-23T00:00:00"
        assert rows["p1"]["active"] is True
        assert rows["p2"]["backfill_days"] == 0

        # effective_applicability must stay a JSON string column, not a
        # struct -- shape varies per prompt (p1 vs p2 differ), so typing it
        # as a struct would risk a schema-merge failure across rows.
        applicability_field = df.schema["effective_applicability"]
        assert applicability_field.dataType.typeName() == "string"
        parsed = json.loads(rows["p1"]["effective_applicability"])
        assert parsed == effective_applicability

        for col in ("s3_key", "ts_load", "year", "month", "day"):
            assert col in df.columns

    def test_returns_none_when_manifest_file_is_absent(self, spark, source_root):
        # Before vocs-machina's first run this fixed-key file may not exist yet.
        df = job.build_prompt_catalog_snapshots_df(spark, str(source_root))
        assert df is None

    def test_duplicate_prompt_id_in_snapshot_is_collapsed_to_one_row(
        self, spark, source_root
    ):
        # A well-formed snapshot lists each prompt_id once, but a duplicate must
        # not survive to the [run_id, prompt_id]-keyed MERGE (two source rows on
        # one target key aborts the Delta MERGE).
        prompt = {
            "prompt_id": "p1",
            "prompt_hash": "h1",
            "classifier_contract_fingerprint": "fp1",
            "effective_applicability": {"any_of": []},
            "active": True,
            "collection": "nps",
            "opportunity": "churn",
            "backfill_days": 7,
        }
        _write_json(
            source_root / "_meta" / "latest_active_prompts.json",
            {
                "generated_at": "2026-08-23T00:00:00",
                "run_id": RUN_ID,
                "prompts": [prompt, dict(prompt)],
            },
        )

        df = job.build_prompt_catalog_snapshots_df(spark, str(source_root))

        assert df is not None
        rows = df.filter(df.prompt_id == "p1").collect()
        assert len(rows) == 1


class TestNoThroughputNoBackfillPlanRun:
    """A single run with a summary but no throughput observation and no
    backfill plan file -- the scenario called out explicitly in the plan and
    required not to raise for either missing artifact."""

    def test_run_summary_present_others_absent_does_not_raise(self, spark, source_root):
        _write_json(
            source_root / "_meta" / "runs" / RUN_ID / "summary.json",
            _run_summary_payload(),
        )

        run_summaries_df = job.build_run_summaries_df(spark, str(source_root))
        throughput_df = job.build_throughput_observations_df(spark, str(source_root))
        backfill_plans_df = job.build_backfill_plans_df(spark, str(source_root))

        assert run_summaries_df is not None
        assert run_summaries_df.collect()[0]["run_id"] == RUN_ID
        assert throughput_df is None
        assert backfill_plans_df is None


class TestEnsureOutputDf:
    """Missing sparse prefixes still produce a writable empty frame so the
    raw Delta table exists for the paired clean LOAD_DELTA task."""

    def test_none_yields_empty_frame_with_populated_columns(self, spark, source_root):
        _write_json(
            source_root / "_meta" / "runs" / RUN_ID / "summary.json",
            _run_summary_payload(),
        )
        populated = job.build_run_summaries_df(spark, str(source_root))
        empty = job.ensure_output_df(spark, "run_summaries", None)

        assert empty.count() == 0
        assert empty.columns == populated.columns

    @pytest.mark.parametrize(
        "table_name",
        [
            "run_summaries",
            "throughput_observations",
            "prompt_catalog_snapshots",
            "backfill_plans",
        ],
    )
    def test_none_for_every_table_has_merge_keys_and_partitions(
        self, spark, table_name
    ):
        empty = job.ensure_output_df(spark, table_name, None)
        assert empty.count() == 0
        for col in job.MERGE_KEYS[table_name]:
            assert col in empty.columns
        for col in ("s3_key", "ts_load", "year", "month", "day"):
            assert col in empty.columns


class TestInsertOnlyMergeContract:
    """Requirement 6 / Plan Task 4: MERGE keys are writer identity and
    matched rows are never updated (no ts_load restamp on rescan).

    These assertions read module constants only -- no SparkSession / JVM.
    """

    def test_merge_keys_match_writer_identity(self):
        assert job.MERGE_KEYS == {
            "run_summaries": ["run_id"],
            "throughput_observations": ["run_id", "observed_at"],
            "prompt_catalog_snapshots": ["run_id", "prompt_id"],
            "backfill_plans": ["run_id"],
        }

    def test_matched_rows_are_never_updated(self):
        assert job.WHEN_MATCHED_UPDATE_CONDITION == "FALSE"

    def test_dual_runtime_clients_are_module_scoped(self):
        assert job.spark_client is not None
        assert job.spark is not None
        assert job.metastore_service is not None
