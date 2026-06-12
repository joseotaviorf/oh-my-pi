from __future__ import annotations

from typing import Sequence

COMMAND_RUNNER_JAR = "command-runner.jar"

# EMR Amazon Linux layout (standard interactive ``spark-submit`` path).
SPARK_SUBMIT_BIN = "/usr/lib/spark/bin/spark-submit"

# Injected before the PySpark URI so they apply to spark-submit (not Python argv).
# Matches ``create_emr_spark_session`` plus ``SPARK_RUNTIME`` for
# ``RuntimeDetector.is_emr()`` on YARN (driver / application master).
_DEFAULT_SPARK_SUBMIT_CONFS: tuple[str, ...] = (
    "--conf",
    "spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension",
    "--conf",
    "spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog",
    "--conf",
    "spark.hadoop.fs.s3a.acl.default=BucketOwnerFullControl",
    "--conf",
    "spark.hadoop.fs.s3a.canned.acl=BucketOwnerFullControl",
    "--conf",
    "spark.yarn.appMasterEnv.SPARK_RUNTIME=emr",
    "--conf",
    "spark.driverEnv.SPARK_RUNTIME=emr",
)


def build_spark_step(
    *,
    name: str,
    action_on_failure: str,
    s3_py_uri: str,
    deploy_mode: str,
    py_script_args: Sequence[str] | None = None,
) -> dict:
    """Build EMR Step dict: command-runner.jar with absolute ``spark-submit`` path.

    Always prepends Delta + S3A ACL + ``SPARK_RUNTIME`` ``--conf`` flags (see
    ``bietlejuice.base.spark.spark_session_factory`` and EMR ``RuntimeDetector``).
    """
    args: list[str] = [
        SPARK_SUBMIT_BIN,
        "--master",
        "yarn",
        "--deploy-mode",
        deploy_mode,
        *_DEFAULT_SPARK_SUBMIT_CONFS,
        s3_py_uri,
    ]
    if py_script_args:
        args.extend(str(a) for a in py_script_args)

    return {
        "Name": name,
        "ActionOnFailure": action_on_failure,
        "HadoopJarStep": {"Jar": COMMAND_RUNNER_JAR, "Args": args},
    }
