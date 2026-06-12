"""Unit tests for ``emr.steps``."""

from __future__ import annotations

from emr.steps import (
    SPARK_SUBMIT_BIN,
    _DEFAULT_SPARK_SUBMIT_CONFS,
    build_spark_step,
)


def test_build_spark_step_appends_py_script_args() -> None:
    step = build_spark_step(
        name="step",
        action_on_failure="CONTINUE",
        s3_py_uri="s3://bucket/job.py",
        deploy_mode="cluster",
        py_script_args=["--target-table", "db.tbl"],
    )
    args = step["HadoopJarStep"]["Args"]
    expected = [
        SPARK_SUBMIT_BIN,
        "--master",
        "yarn",
        "--deploy-mode",
        "cluster",
        *_DEFAULT_SPARK_SUBMIT_CONFS,
        "s3://bucket/job.py",
        "--target-table",
        "db.tbl",
    ]
    assert args == expected
