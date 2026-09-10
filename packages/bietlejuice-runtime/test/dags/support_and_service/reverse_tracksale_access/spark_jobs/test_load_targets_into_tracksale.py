"""Unit tests for the dispatch-marking retry in ``load_targets_into_tracksale``.

Losing the is_dispatched marking after Tracksale accepted a payload makes the
next run re-send the same customers, so these tests lock the retry policy, the
error log that must reach ``datalake_sst_metrics.api_logs`` when it is
exhausted, and the guard that reuses an already accepted dispatch instead of
POSTing again when Airflow retries the task.

Run::

    pytest packages/bietlejuice-runtime/test/dags/support_and_service/reverse_tracksale_access/spark_jobs/ -q
"""

import importlib
import json
from datetime import date, datetime
from unittest.mock import MagicMock, patch

import pytest

_MODULE_PATH = "dags.support_and_service.reverse_tracksale_access.spark_jobs.load_targets_into_tracksale"

# The job builds a SparkClient and reads Databricks secrets at import time.
_IMPORT_TIME_MOCKS = {
    "pyspark": MagicMock(),
    "pyspark.sql": MagicMock(),
    "pyspark.sql.types": MagicMock(),
    "quintoandar_logger": MagicMock(),
    "quintoandar_tracksale_api_client": MagicMock(),
    "quintoandar_tracksale_api_client.clients": MagicMock(),
    "quintoandar_tracksale_api_client.requesters": MagicMock(),
    "bietlejuice.base.api.api_enum": MagicMock(),
    "bietlejuice.base.spark": MagicMock(),
    "bietlejuice.base.validation.spark_args": MagicMock(),
    "bietlejuice.base.sst.domains.salesforce.api.api_logs": MagicMock(),
    "bietlejuice.clients.db_clients": MagicMock(),
    "bietlejuice.services.configuration_service": MagicMock(),
}

with patch.dict("sys.modules", _IMPORT_TIME_MOCKS):
    _job = importlib.import_module(_MODULE_PATH)


_CHUNK = {
    "dispatch_code": "Dispatch_code",
    "status": {"inserted": 3, "invalid": 1, "duplicated": 0},
}
_DISPATCH_RESULT = {
    "campaign_code": 242,
    "chunks": [_CHUNK],
    "status": {"inserted": 3, "invalid": 1, "duplicated": 0},
    "dispatch_codes": ["Dispatch_code"],
}


def _main_patches(**overrides) -> dict:
    """Baseline patches that let ``main`` reach the dispatch and marking section."""
    dbutils = MagicMock()
    dbutils.secrets.get.return_value = json.dumps({"token": "token"})

    patches = {
        "parse_arguments": MagicMock(
            return_value=(
                "reverse_tracksale_access",
                "reverse_tracksale_test",
                "lost_pp",
                datetime.combine(date.today(), datetime.min.time()),
                None,
                None,
            )
        ),
        "is_validation_run": MagicMock(return_value=False),
        "get_campaign": MagicMock(
            return_value={
                "campaign_code": 242,
                "tags": "[]",
                "trigger_at_hour": 17,
                "trigger_at_minute": 0,
            }
        ),
        "get_pending_rows": MagicMock(
            return_value=([{"customer_email": "a@b.c"}], set(), 1)
        ),
        "build_payload": MagicMock(return_value={"customers": []}),
        "get_previously_accepted_dispatch": MagicMock(return_value=None),
        "send_targets_to_tracksale": MagicMock(return_value=_DISPATCH_RESULT),
        "mark_campaign_targets_as_dispatched_with_retry": MagicMock(),
        "save_tracksale_api_logs": MagicMock(),
        "ConfigurationService": MagicMock(),
        "dbutils": dbutils,
    }
    patches.update(overrides)
    return patches


class TestMarkCampaignTargetsAsDispatchedWithRetry:
    def _call(self):
        _job.mark_campaign_targets_as_dispatched_with_retry(
            "reverse_tracksale_test", "lost_pp", datetime(2026, 8, 17), set()
        )

    def test_does_not_retry_when_first_attempt_succeeds(self):
        mark = MagicMock()

        with (
            patch.object(_job, "mark_campaign_targets_as_dispatched", mark),
            patch.object(_job, "time") as fake_time,
        ):
            self._call()

        assert mark.call_count == 1
        fake_time.sleep.assert_not_called()

    def test_retries_until_it_succeeds(self):
        mark = MagicMock(side_effect=[Exception("delta conflict"), None])

        with (
            patch.object(_job, "mark_campaign_targets_as_dispatched", mark),
            patch.object(_job, "time") as fake_time,
        ):
            self._call()

        assert mark.call_count == 2
        assert fake_time.sleep.call_count == 1

    def test_raises_after_exhausting_the_configured_attempts(self):
        mark = MagicMock(
            side_effect=[
                Exception("delta conflict 1"),
                Exception("delta conflict 2"),
                Exception("delta conflict 3"),
            ]
        )

        with (
            patch.object(_job, "mark_campaign_targets_as_dispatched", mark),
            patch.object(_job, "time") as fake_time,
        ):
            with pytest.raises(Exception, match="delta conflict 3"):
                self._call()

        assert _job.MARK_DISPATCH_MAX_ATTEMPTS == 3
        assert mark.call_count == _job.MARK_DISPATCH_MAX_ATTEMPTS
        # No wait after the final failure.
        assert fake_time.sleep.call_count == _job.MARK_DISPATCH_MAX_ATTEMPTS - 1


class TestBuildTracksaleApiLogRows:
    def test_success_rows_carry_no_error(self):
        rows = _job.build_tracksale_api_log_rows(_DISPATCH_RESULT)

        assert len(rows) == 1
        assert rows[0]["success"] is True
        assert rows[0]["error"] is None
        assert rows[0]["id_record"] == "Dispatch_code"

    def test_marking_error_keeps_the_api_payload(self):
        rows = _job.build_tracksale_api_log_rows(
            _DISPATCH_RESULT, error=Exception("delta conflict")
        )

        assert len(rows) == 1
        assert rows[0]["success"] is False
        assert "delta conflict" in rows[0]["error"]
        # The API counters must survive for forensics.
        assert json.loads(rows[0]["api_logs"])["status"]["inserted"] == 3


class TestGetAcceptedDispatchChunkLogs:
    def test_query_only_accepts_logged_http_200_within_the_lookback(self):
        fake_spark = MagicMock()
        fake_spark.sql.return_value.collect.return_value = [
            MagicMock(api_logs=json.dumps(_CHUNK))
        ]

        with patch.object(_job, "spark", fake_spark):
            chunk_logs = _job.get_accepted_dispatch_chunk_logs(
                "242", "reverse_tracksale_test.lost_pp", "dag.job", "2026-08-17"
            )

        assert chunk_logs == [json.dumps(_CHUNK)]
        query = fake_spark.sql.call_args.args[0]
        # A chunk logged with 200 proves Tracksale accepted the customers even when the
        # run later failed, so success must not be part of the filter.
        assert "status_code = 200" in query
        assert "success" not in query
        assert "partition_date = '2026-08-17'" in query
        assert "entity_type = '242'" in query
        assert "target_table = 'reverse_tracksale_test.lost_pp'" in query
        assert "TO_TIMESTAMP(load_ts) >=" in query


class TestRebuildDispatchResult:
    def test_aggregates_counters_across_logged_chunks(self):
        result = _job.rebuild_dispatch_result(
            [
                json.dumps(_CHUNK),
                json.dumps(
                    {
                        "dispatch_code": "Other_code",
                        "status": {"inserted": 2, "invalid": 0, "duplicated": 5},
                    }
                ),
            ]
        )

        assert result["status"] == {"inserted": 5, "invalid": 1, "duplicated": 5}
        assert len(result["chunks"]) == 2

    def test_returns_none_when_nothing_usable_was_logged(self):
        assert _job.rebuild_dispatch_result([]) is None
        assert _job.rebuild_dispatch_result(["not json"]) is None


class TestGetPreviouslyAcceptedDispatch:
    def _call(self):
        return _job.get_previously_accepted_dispatch(
            "242", "reverse_tracksale_test.lost_pp", "dag.job", "2026-08-17"
        )

    def test_reuses_the_accepted_dispatch_when_one_was_logged(self):
        with patch.object(
            _job,
            "get_accepted_dispatch_chunk_logs",
            MagicMock(return_value=[json.dumps(_CHUNK)]),
        ):
            assert self._call()["status"]["inserted"] == 3

    def test_degrades_to_none_when_the_log_cannot_be_read(self):
        # api_logs does not exist before the first dispatch of an environment, and a
        # failed log read must not block the daily run.
        with patch.object(
            _job,
            "get_accepted_dispatch_chunk_logs",
            MagicMock(side_effect=Exception("Table or view not found")),
        ):
            assert self._call() is None


class TestMainMarkingFailure:
    def test_persists_error_log_then_reraises(self):
        marking_error = RuntimeError("delta conflict")

        with patch.multiple(
            _job,
            **_main_patches(
                mark_campaign_targets_as_dispatched_with_retry=MagicMock(
                    side_effect=marking_error
                )
            ),
        ):
            with pytest.raises(RuntimeError, match="delta conflict"):
                _job.main()

            _job.save_tracksale_api_logs.assert_called_once()
            log_rows = _job.save_tracksale_api_logs.call_args.kwargs["log_rows"]

        assert len(log_rows) == 1
        assert log_rows[0]["success"] is False
        assert "delta conflict" in log_rows[0]["error"]


class TestMainReusesAcceptedDispatch:
    """An Airflow task retry must recover the marking, never re-send the customers."""

    def test_skips_the_post_and_only_retries_the_marking(self):
        with patch.multiple(
            _job,
            **_main_patches(
                get_previously_accepted_dispatch=MagicMock(
                    return_value=_DISPATCH_RESULT
                )
            ),
        ):
            _job.main()

            _job.send_targets_to_tracksale.assert_not_called()
            _job.mark_campaign_targets_as_dispatched_with_retry.assert_called_once()
            log_rows = _job.save_tracksale_api_logs.call_args.kwargs["log_rows"]

        # The reused dispatch is logged as the success it now is, keeping the counters
        # Tracksale originally answered.
        assert len(log_rows) == 1
        assert log_rows[0]["success"] is True
        assert log_rows[0]["error"] is None
        assert json.loads(log_rows[0]["api_logs"])["status"]["inserted"] == 3

    def test_still_fails_when_the_marking_keeps_failing(self):
        with patch.multiple(
            _job,
            **_main_patches(
                get_previously_accepted_dispatch=MagicMock(
                    return_value=_DISPATCH_RESULT
                ),
                mark_campaign_targets_as_dispatched_with_retry=MagicMock(
                    side_effect=RuntimeError("delta conflict")
                ),
            ),
        ):
            with pytest.raises(RuntimeError, match="delta conflict"):
                _job.main()

            _job.send_targets_to_tracksale.assert_not_called()
            log_rows = _job.save_tracksale_api_logs.call_args.kwargs["log_rows"]

        assert log_rows[0]["success"] is False
