"""EMR-only SparkSession builder (Delta + Hive). Databricks keeps injected session."""

from __future__ import annotations

import os
import sys
import threading
import time
import traceback
from typing import Any, Callable, Dict, List, Optional

from pyspark.sql import SparkSession

_DELTA_SPARK_SQL_EXTENSIONS = "io.delta.sql.DeltaSparkSessionExtension"

# Measured on j-0835817ZSRL6JVJLDX9 (2026-08-07): a healthy SparkSession.stop() takes
# under 1 s to 2 s. 30 s is 15x the worst observed value, so it never fires on a good
# run, and it is far below the smallest configured execution_timeout (30 min) so a
# wedged driver is killed here rather than by Airflow. The ETL work is already
# committed before stop() is called, so a forced exit at the cap loses no data --
# only the OpenLineage COMPLETE event and the event-log finalisation for that run.
SPARK_STOP_TIMEOUT_SECONDS = 30


def _merge_spark_sql_extensions(*extension_lists: Optional[str]) -> str:
    """Join comma-separated extension class names without duplicates."""
    merged: List[str] = []
    for extension_list in extension_lists:
        if not extension_list:
            continue
        for extension in extension_list.split(","):
            extension = extension.strip()
            if extension and extension not in merged:
                merged.append(extension)
    return ",".join(merged)


def create_emr_spark_session(
    app_name: str,
    extra_configs: Optional[Dict[str, Any]] = None,
) -> SparkSession:
    configs = dict(extra_configs or {})
    cluster_extensions = configs.pop("spark.sql.extensions", None)
    merged_extensions = _merge_spark_sql_extensions(
        _DELTA_SPARK_SQL_EXTENSIONS,
        cluster_extensions,
    )
    builder = (
        SparkSession.builder.appName(app_name)
        .config("spark.sql.extensions", merged_extensions)
        .config(
            "spark.sql.catalog.spark_catalog",
            "org.apache.spark.sql.delta.catalog.DeltaCatalog",
        )
        .config("spark.hadoop.fs.s3a.acl.default", "BucketOwnerFullControl")
        .config("spark.hadoop.fs.s3a.canned.acl", "BucketOwnerFullControl")
        .enableHiveSupport()
    )
    for key, value in configs.items():
        builder = builder.config(key, value)
    return builder.getOrCreate()


def _flush_stdio() -> None:
    """Flush buffered stdout/stderr before os._exit, which skips normal shutdown."""
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.flush()
        except Exception:  # noqa: BLE001 - never block the hard exit
            pass


def _exit_code_from_system_exit(exc: SystemExit) -> int:
    code = exc.code
    if code in (None, 0):
        return 0
    if isinstance(code, int):
        return 0 if code == 0 else 1
    return 1


def run_spark_entrypoint(
    entrypoint: Callable[[], None],
    stop_timeout_seconds: int = SPARK_STOP_TIMEOUT_SECONDS,
) -> None:
    """Run a spark job's ``main`` under the current runtime.

    On EMR, also bound ``SparkSession.stop()`` and hard-exit the driver so a
    wedged shutdown cannot leave the step RUNNING. On Databricks, run
    ``entrypoint`` and return (or ``SystemExit`` on failure) without stopping
    the injected session.

    Exit code is 0 on success and 1 on any exception, matching the previous
    ``try/finally`` behaviour where a raised exception failed the EMR step.
    """
    from bietlejuice.base.spark.runtime_detector import RuntimeDetector

    exit_code = 0
    try:
        entrypoint()
    except SystemExit as exc:  # preserve sys.exit / argparse status
        exit_code = _exit_code_from_system_exit(exc)
    except BaseException:  # noqa: BLE001 - must map every failure to a non-zero exit
        traceback.print_exc()
        exit_code = 1

    if not RuntimeDetector.is_emr():
        if exit_code:
            raise SystemExit(exit_code)
        return

    # Resolve the session on THIS thread: SparkSession.getActiveSession() delegates to a
    # JVM thread-local, so calling it from the stopper thread would return None.
    session = None
    try:
        session = SparkSession.getActiveSession()
    except BaseException:  # noqa: BLE001 - a dead JVM must not block the exit
        traceback.print_exc()
    if session is None:
        sys.stderr.write(
            f"No active SparkSession; skipping stop() and exiting driver with code {exit_code}\n"
        )
        _flush_stdio()
        os._exit(exit_code)

    def _stop(sess: SparkSession) -> None:
        try:
            sess.stop()
        except BaseException:  # noqa: BLE001 - a failed stop must not change the exit code
            traceback.print_exc()

    stopper = threading.Thread(
        target=_stop, args=(session,), name="emr-spark-stop", daemon=True
    )
    started = time.monotonic()
    stopper.start()
    stopper.join(stop_timeout_seconds)
    if stopper.is_alive():
        sys.stderr.write(
            f"SparkSession.stop() still running after {stop_timeout_seconds}s; data work "
            f"already committed, forcing driver exit with code {exit_code}\n"
        )
    else:
        sys.stderr.write(
            f"SparkSession.stop() finished in {time.monotonic() - started:.1f}s; "
            f"exiting driver with code {exit_code}\n"
        )
    _flush_stdio()
    os._exit(exit_code)
