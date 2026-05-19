"""Regression tests for event-log S3 key → ``id_spark_app`` extraction.

PySpark ``regexp_extract`` uses Java regex; we validate the same pattern with
Python ``re`` for cheap CI coverage (this pattern is ASCII-only and compatible).

::

    pytest packages/bietlejuice-runtime/test/unit/enrich_spark_event_logs/test_spark_event_log_path_patterns.py -q
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import pytest

_REPO_ROOT = Path(__file__).resolve().parents[5]
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from dags.platform.enrich_spark_event_logs.spark_jobs.load_spark_stage_metrics import (  # noqa: E402
    EVENTLOG_APP_ID_SEGMENT_PATTERN,
)


@pytest.mark.parametrize(
    ("file_path", "expected_id"),
    [
        (
            "s3a://b/spark-event-logs/bietlejuice.big_agent_fast_lane/"
            "eventlog_v2_local-1779162723207/events_4_local-1779162723207.zstd",
            "local-1779162723207",
        ),
        (
            "s3a://b/spark-event-logs/quintoml.wonka.user_visits/"
            "eventlog_v2_app-20260519083350-0000/events_1.zstd",
            "app-20260519083350-0000",
        ),
        (
            "s3://b/spark-event-logs/xdag/eventlog-v2-myapp-attempt/events_1.zstd",
            "myapp-attempt",
        ),
        (
            "s3://b/spark-event-logs/xdag/eventlog-legacy_attempt_only/events.zstd",
            "legacy_attempt_only",
        ),
    ],
)
def test_eventlog_segment_extracts_app_id(file_path: str, expected_id: str) -> None:
    matched = re.search(EVENTLOG_APP_ID_SEGMENT_PATTERN, file_path)
    assert matched is not None, file_path
    assert matched.group(1) == expected_id
